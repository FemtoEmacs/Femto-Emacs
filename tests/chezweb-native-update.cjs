// M-x native-window-update (logbook, 9 November 2026): a browser save refused
// because the native buffer was edited, closed, saved under another name or
// made read-only says which, and the browser's text can then be put in the
// native buffer -- native text that is on no disk kept in *native-N* -- so
// that C-x C-s saves.  No browser, real PTYs, all files disposable.
const fs=require('fs'),os=require('os'),path=require('path'),cp=require('child_process'),assert=require('assert');
const root=path.resolve(__dirname,'..'),work=fs.mkdtempSync(path.join(os.tmpdir(),'chezweb-native-update-'));
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
  const snapshot=await fetch(url+'snapshot');assert.equal(snapshot.status,200);const text=await snapshot.text();let revision=snapshot.headers.get('X-Chezweb-Revision');assert.equal(revision,'0');assert.equal(snapshot.headers.get('X-Chezweb-Modified'),exists&&!unnamed&&!initialEdit?'0':'1');
  return {dir,file,url,text,trigger,release,screen,
   async put(body,version=revision){const r=await fetch(url+'save',{method:'PUT',headers:{Origin:origin,'Content-Type':'application/x-chezweb-text','X-Chezweb-Revision':version},body});const message=await r.text();if(r.ok)revision=r.headers.get('X-Chezweb-Revision');return {status:r.status,message,revision};},
   async close(){fs.writeFileSync(finish,'done');assert.equal(await exited,0,fs.readFileSync(screen,'utf8').slice(-1500));},
   async update(body){const r=await fetch(url+'update',{method:'PUT',headers:{Origin:origin,'Content-Type':'application/x-chezweb-text'},body});const message=await r.text();if(r.ok)revision=r.headers.get('X-Chezweb-Revision');return {status:r.status,message,revision};},
   async refresh(){return fetch(url+'refresh',{method:'POST',headers:{Origin:origin,'Content-Type':'application/x-chezweb-refresh'}});}
  };
 }catch(e){fs.writeFileSync(finish,'done');proc.kill('SIGTERM');throw e;}
}
(async()=>{try{
 const cc=cp.spawnSync(process.env.CC||'cc',['-O2',path.join(root,'tests/pty-keys.c'),'-o',path.join(work,'pty')]);assert.equal(cc.status,0);
 const ready=async(c,what,mark)=>{fs.writeFileSync(c.trigger,what);try{await until(()=>fs.readFileSync(c.screen,'utf8').includes(mark),mark);}catch(e){console.error(fs.readFileSync(c.screen,'utf8').slice(-1500));throw e;}};
 let c=await start('edited',{commands:'keys NATIVE \nkeys \\e:(quote NATIVE-READY)\\r\nawait-file $RELEASE\nkeys \\e:(list (quote SHOWN) (buffer-substring 0 (buffer-size)))\\r\nkeys ^Xb*native-1*\\r\nkeys \\e:(list (quote KEPT) (buffer-substring 0 (buffer-size)))\\r',clean:false});await ready(c,'edit','NATIVE-READY');
 let r=await c.put('BROWSER\n');assert.equal(r.status,409);assert.match(r.message,/edited after C-c d/);assert.match(r.message,/native-window-update/);
 r=await c.update('BROWSER\n');assert.equal(r.status,200,r.message);assert.match(r.message,/its own text is in \*native-1\*/);assert.equal(fs.readFileSync(c.file,'utf8'),'ORIGINAL\n','an update writes no file');
 r=await c.put('BROWSER\n');assert.equal(r.status,200,r.message);assert.equal(fs.readFileSync(c.file,'utf8'),'BROWSER\n');
 fs.writeFileSync(c.release,'check');await until(()=>fs.readFileSync(c.screen,'utf8').includes('KEPT'),'native buffers checked');await sleep(300);
 const seen=fs.readFileSync(c.screen,'utf8');assert.match(seen,/SHOWN "BROWSER/);assert.match(seen,/KEPT "NATIVE ORIGINAL/);
 await c.close();console.log('PASS edited native buffer: the refusal says so; native-window-update keeps the native text in *native-1*; C-x C-s then saves');
 c=await start('closed',{commands:'keys ^Xk\nkeys \\e:(quote CLOSED-READY)\\r',clean:false});await ready(c,'close','CLOSED-READY');
 r=await c.put('AFTER CLOSE\n');assert.equal(r.status,409);assert.match(r.message,/was closed/);
 r=await c.update('AFTER CLOSE\n');assert.equal(r.status,200,r.message);assert.doesNotMatch(r.message,/\*native-/,'the closed buffer text was on disk');
 r=await c.put('AFTER CLOSE\n');assert.equal(r.status,200,r.message);assert.equal(fs.readFileSync(c.file,'utf8'),'AFTER CLOSE\n');
 await c.close();console.log('PASS closed native buffer: native-window-update opens the file again with the browser text; C-x C-s then saves');
 c=await start('renamed',{commands:'keys ^X^W\nwait 100\nkeys ^A^K$NEWFILE\\r\nkeys \\e:(quote RENAME-READY)\\r',clean:false});await ready(c,'rename','RENAME-READY');
 r=await c.put('ORIGINAL TARGET\n');assert.equal(r.status,409);assert.match(r.message,/saved under another name/);
 r=await c.update('ORIGINAL TARGET\n');assert.equal(r.status,200,r.message);r=await c.put('ORIGINAL TARGET\n');assert.equal(r.status,200,r.message);
 assert.equal(fs.readFileSync(c.file,'utf8'),'ORIGINAL TARGET\n');assert.equal(fs.readFileSync(path.join(c.dir,'renamed.md'),'utf8'),'ORIGINAL\n');
 await c.close();console.log('PASS buffer saved under another name: the update goes to the original file, the renamed copy is untouched');
 c=await start('readonly',{commands:'keys ^X^Q\nkeys \\e:(quote READ-READY)\\r'});await ready(c,'read','READ-READY');
 r=await c.put('BLOCKED\n');assert.equal(r.status,409);assert.match(r.message,/read-only\. .*C-x C-q in the native window/);
 r=await c.update('BLOCKED\n');assert.equal(r.status,409);assert.match(r.message,/Not updated: the native buffer is read-only/);assert.equal(fs.readFileSync(c.file,'utf8'),'ORIGINAL\n');
 await c.close();console.log('PASS a read-only native buffer is not updated, and says how to make it writable');
 c=await start('disk',{clean:false});fs.writeFileSync(c.file,'EXTERNAL\n');
 r=await c.update('BROWSER\n');assert.equal(r.status,200,r.message);assert.match(r.message,/changed on disk since C-c d/);assert.equal(fs.readFileSync(c.file,'utf8'),'EXTERNAL\n');
 r=await c.put('BROWSER\n');assert.equal(r.status,409);assert.equal(fs.readFileSync(c.file,'utf8'),'EXTERNAL\n');
 await c.close();console.log('PASS an update never writes the disk; a file changed on disk is still not overwritten from the browser');
 c=await start('stale',{clean:false});assert.equal((await c.put('NEWER\n')).status,200);
 r=await c.update('OLDER\n');assert.equal(r.status,200,r.message);assert.doesNotMatch(r.message,/\*native-/,'NEWER is on disk');
 await c.close();console.log('PASS native text already on disk is not copied again');
 console.log('PASS native-window-update suite');
}finally{
 for(const r of running)if(r.proc.exitCode===null){try{fs.writeFileSync(r.release,'done');fs.writeFileSync(r.finish,'done');}catch(_){}await Promise.race([r.exited,sleep(1500)]);if(r.proc.exitCode===null)r.proc.kill('SIGTERM');}
 fs.rmSync(work,{recursive:true,force:true});}})().catch(e=>{console.error(e);process.exitCode=1;});
