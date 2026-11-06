// Fixed-source native persistence: no browser, real PTYs, all files disposable.
const fs=require('fs'),os=require('os'),path=require('path'),cp=require('child_process'),assert=require('assert');
const root=path.resolve(__dirname,'..'),work=fs.mkdtempSync(path.join(os.tmpdir(),'chezweb-save-native-'));
const running=[];
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function until(pred,message){for(let i=0;i<400;i++){if(await pred())return;await sleep(25);}throw Error(message);}
async function start(name,{exists=true,filename='nia.md',commands='',initialEdit='',clean=true,unnamed=false}={}){
 const dir=path.join(work,name);fs.mkdirSync(dir);const bin=path.join(dir,'bin');fs.mkdirSync(bin);
 fs.writeFileSync(path.join(bin,'browser-fixture'),'#!/bin/sh\nprintf "%s\\n" "$1" > "$CHEZWEB_TEST_URL"\n',{mode:0o755});
 const file=path.join(dir,filename),urlFile=path.join(dir,'url'),finish=path.join(dir,'finish'),trigger=path.join(dir,'trigger'),release=path.join(dir,'release'),screen=path.join(dir,'screen');
 if(exists&&!unnamed)fs.writeFileSync(file,'ORIGINAL\n');
 const script='await-screen C-h help\n'+initialEdit+'keys ^Cd\n'+(commands?'await-file '+trigger+'\n'+commands.replaceAll('$RELEASE',release).replaceAll('$NEWFILE',path.join(dir,'renamed.md'))+'\n':'')+'await-file '+finish+'\nkeys ^X^C'+(clean?'':'y')+'\n';
 fs.writeFileSync(path.join(dir,'keys'),script);
 const proc=cp.spawn(path.join(work,'pty'),[path.join(dir,'keys'),'90',screen,path.join(root,'chezweb'),...(unnamed?[]:[file])],{cwd:root,env:{...process.env,HOME:dir,CHEZEMAX_NO_INIT:'1',CHEZWEB_BROWSER:'browser-fixture',CHEZWEB_TEST_URL:urlFile,PATH:bin+path.delimiter+process.env.PATH}});
 const exited=new Promise(r=>proc.on('exit',r));running.push({proc,finish,release,exited});
 try{
  await until(()=>fs.existsSync(urlFile),'native server launch');const url=fs.readFileSync(urlFile,'utf8').trim(),origin=new URL(url).origin;
  const snapshot=await fetch(url+'snapshot');assert.equal(snapshot.status,200);const text=await snapshot.text();let revision=snapshot.headers.get('X-Chezweb-Revision');assert.equal(revision,'0');
  return {dir,file,url,text,trigger,release,screen,
   async put(body,version=revision){const r=await fetch(url+'save',{method:'PUT',headers:{Origin:origin,'Content-Type':'application/x-chezweb-text','X-Chezweb-Revision':version},body});const message=await r.text();if(r.ok)revision=r.headers.get('X-Chezweb-Revision');return {status:r.status,message,revision};},
   async close(){fs.writeFileSync(finish,'done');assert.equal(await exited,0,fs.readFileSync(screen,'utf8').slice(-1500));},
   async refresh(){return fetch(url+'refresh',{method:'POST',headers:{Origin:origin,'Content-Type':'application/x-chezweb-refresh'}});}
  };
 }catch(e){fs.writeFileSync(finish,'done');proc.kill('SIGTERM');throw e;}
}
(async()=>{try{
 const cc=cp.spawnSync(process.env.CC||'cc',['-O2',path.join(root,'tests/pty-keys.c'),'-o',path.join(work,'pty')]);assert.equal(cc.status,0);
 let c=await start('normal');fs.chmodSync(c.file,0o640);
 for(const text of ['Browser é🙂\n','Second revision\n','']){const r=await c.put(text);assert.equal(r.status,200,r.message);assert.equal(fs.readFileSync(c.file,'utf8'),text);assert.equal(fs.statSync(c.file).mode&0o777,0o640);}
 assert.equal((await fetch(c.url+'snapshot')).headers.get('X-Chezweb-Revision'),'3');await c.close();console.log('PASS idle native commit, repeated UTF-8/empty saves, clean quit and file permissions');
 c=await start('spaces',{filename:'Nia café.md'});assert.equal((await c.put('Space/Unicode path\n')).status,200);assert.equal(fs.readFileSync(c.file,'utf8'),'Space/Unicode path\n');await c.close();console.log('PASS original filenames with spaces and Unicode');
 c=await start('unsaved',{initialEdit:'keys PREEXISTING \n'});assert(c.text.startsWith('PREEXISTING '));assert.equal((await c.put('Browser '+c.text)).status,200);assert.equal(fs.readFileSync(c.file,'utf8'),'Browser '+c.text);await c.close();console.log('PASS unsaved native text at handoff is included in the first disk save');
 c=await start('native-conflict',{commands:'keys NATIVE \nkeys \\e:(quote NATIVE-READY)\\r',clean:false});fs.writeFileSync(c.trigger,'edit');await until(()=>fs.readFileSync(c.screen,'utf8').includes('NATIVE-READY'),'native concurrent edit');let r=await c.put('BROWSER\n');assert.equal(r.status,409,r.message);assert.equal(fs.readFileSync(c.file,'utf8'),'ORIGINAL\n');assert.equal((await c.put('SECOND BROWSER\n')).status,409);assert.equal((await c.put('SECOND BROWSER\n')).status,409);await c.close();console.log('PASS native concurrent edits reject overwrite and preserve browser conflict text');
 c=await start('disk-conflict');fs.writeFileSync(c.file,'EXTERNAL\n');r=await c.put('BROWSER\n');assert.equal(r.status,409);assert.equal(fs.readFileSync(c.file,'utf8'),'EXTERNAL\n');await c.close();console.log('PASS external disk changes reject overwrite');
 c=await start('permission');fs.chmodSync(c.file,0o444);r=await c.put('RETRY\n');assert.equal(r.status,500);assert.equal(fs.readFileSync(c.file,'utf8'),'ORIGINAL\n');fs.chmodSync(c.file,0o644);r=await c.put('RETRY\n');assert.equal(r.status,200,r.message);assert.equal(fs.readFileSync(c.file,'utf8'),'RETRY\n');await c.close();console.log('PASS denied writes leave disk intact and a later retry succeeds');
 c=await start('new',{exists:false});assert.equal((await c.put('NEW\n')).status,200);assert.equal(fs.readFileSync(c.file,'utf8'),'NEW\n');await c.close();console.log('PASS explicitly saving a named new file creates only its fixed source target');
 c=await start('refresh');fs.writeFileSync(c.file,'LOCAL HANDLE SAVE\n');assert.equal((await c.refresh()).status,200);await until(async()=>await (await fetch(c.url+'snapshot')).text()==='LOCAL HANDLE SAVE\n','native local-save refresh');r=await c.put('STALE\n','0');assert.equal(r.status,409);assert.equal(fs.readFileSync(c.file,'utf8'),'LOCAL HANDLE SAVE\n');await c.close();console.log('PASS direct local saves refresh native text and stale browser revisions cannot overwrite them');
 c=await start('readonly',{commands:'keys ^X^Q\nkeys \\e:(quote READ-READY)\\r'});fs.writeFileSync(c.trigger,'read');await until(()=>fs.readFileSync(c.screen,'utf8').includes('READ-READY'),'read-only mode');assert.equal((await c.put('BLOCKED\n')).status,409);assert.equal(fs.readFileSync(c.file,'utf8'),'ORIGINAL\n');await c.close();console.log('PASS read-only native buffers reject browser mutation');
 c=await start('busy',{commands:'keys ^X^F\nawait-file $RELEASE\nkeys ^G'});fs.writeFileSync(c.trigger,'prompt');await until(()=>fs.readFileSync(c.screen,'utf8').includes('Find file'),'native filename prompt');r=await c.put('BUSY\n');assert.equal(r.status,503);fs.writeFileSync(c.release,'resume');await sleep(250);assert.equal(fs.readFileSync(c.file,'utf8'),'ORIGINAL\n','timed-out saves must not commit after the prompt closes');assert.equal((await c.put('AFTER PROMPT\n')).status,200);await c.close();console.log('PASS prompts prevent reentrant saves; timed-out requests are cancelled and retry works');
 c=await start('renamed',{commands:'keys ^X^W\nwait 100\nkeys ^A^K$NEWFILE\\r\nkeys \\e:(quote RENAME-READY)\\r'});fs.writeFileSync(c.trigger,'rename');await until(()=>fs.readFileSync(c.screen,'utf8').includes('RENAME-READY'),'native Save As');assert.equal((await c.put('WRONG TARGET\n')).status,409);assert.equal(fs.readFileSync(c.file,'utf8'),'ORIGINAL\n');assert.equal(fs.readFileSync(path.join(c.dir,'renamed.md'),'utf8'),'ORIGINAL\n');await c.close();console.log('PASS native Save As cannot silently retarget an existing browser session');
 c=await start('untitled',{unnamed:true});assert.equal((await c.put('NO NAME\n')).status,422);assert(!fs.existsSync(c.file));await c.close();console.log('PASS unnamed native buffers require an explicit Save As target');
 c=await start('closed',{commands:'keys ^Xk\nkeys \\e:(quote CLOSED-READY)\\r'});fs.writeFileSync(c.trigger,'close');await until(()=>fs.readFileSync(c.screen,'utf8').includes('CLOSED-READY'),'closed native source');assert.equal((await c.put('CLOSED SOURCE\n')).status,409);assert.equal(fs.readFileSync(c.file,'utf8'),'ORIGINAL\n');await c.close();console.log('PASS closing the native source cannot redirect a browser save to another buffer');
 c=await start('versions');assert.equal((await c.put('v1\n')).status,200);assert.equal((await c.put('stale second browser\n','0')).status,409);assert.equal(fs.readFileSync(c.file,'utf8'),'v1\n');assert.equal((await c.put('v2\n')).status,200);await c.close();console.log('PASS independent stale browser versions cannot clobber a newer committed save');
 console.log('PASS fixed-source native save suite');
}finally{
 for(const r of running)if(r.proc.exitCode===null){try{fs.writeFileSync(r.release,'done');fs.writeFileSync(r.finish,'done');}catch(_){}await Promise.race([r.exited,sleep(1500)]);if(r.proc.exitCode===null)r.proc.kill('SIGTERM');}
 fs.rmSync(work,{recursive:true,force:true});}})().catch(e=>{console.error(e);process.exitCode=1;});
