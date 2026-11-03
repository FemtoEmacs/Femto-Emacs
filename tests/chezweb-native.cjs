// Native terminal + local server, disposable HOME/files, no actual browser
// launcher or AI invocation. Chrome itself is covered by chezweb-web.cjs.
const fs=require('fs'),os=require('os'),path=require('path'),cp=require('child_process'),assert=require('assert');
const root=path.resolve(__dirname,'..'),work=fs.mkdtempSync(path.join(os.tmpdir(),'chezweb-native-test-'));
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function run(conflict){
 const dir=path.join(work,conflict?'conflict':'normal');fs.mkdirSync(dir);const fixture=path.join(dir,'fixture.md'),other=path.join(dir,'conflict.txt');fs.writeFileSync(fixture,'Native original\n');
  const bin=path.join(dir,'bin'),launchLog=path.join(dir,'launched-url');fs.mkdirSync(bin);
 const browserName=process.platform==='linux'?'google-chrome':'fixture-browser';
 fs.writeFileSync(path.join(bin,browserName),"#!/bin/sh\nprintf '%s\\n' \"$1\" > \"$CHEZWEB_TEST_LAUNCH_LOG\"\n",{mode:0o755});
 const launchEnv={...process.env,HOME:dir,CHEZEMAX_NO_INIT:'1',PATH:bin+path.delimiter+process.env.PATH,CHEZWEB_TEST_LAUNCH_LOG:launchLog};
 if(process.platform==='linux')delete launchEnv.CHEZWEB_BROWSER;else launchEnv.CHEZWEB_BROWSER=browserName;
 const before=new Set(fs.readdirSync('/tmp').filter(n=>n.startsWith('chezweb-session-')));
 let script='wait 1500\nkeys ^Cd\n';
 if(conflict)script+='wait 500\nkeys local \n';
 script+='wait 6000\nkeys ^L\nwait 500\n';
 if(conflict)script+='keys ^X^W\nwait 300\nkeys ^A^K'+other+'\\r\nwait 500\nkeys ^Xb\nwait 300\nkeys fixture.md\\r\nwait 300\n';
 script+='keys ^X^S\nwait 500\nkeys ^X^C\n';
 const keys=path.join(dir,'keys'),screen=path.join(dir,'screen');fs.writeFileSync(keys,script);
 const proc=cp.spawn(path.join(work,'pty-keys'),[keys,'25',screen,path.join(root,'chezweb'),fixture],{cwd:root,env:launchEnv,stdio:'inherit'});
 const exited=new Promise(r=>proc.on('exit',r));let session;
 for(let n=0;n<150&&!session;n++){for(const name of fs.readdirSync('/tmp'))if(name.startsWith('chezweb-session-')&&!before.has(name)&&fs.existsSync(path.join('/tmp',name,'ready')))session=path.join('/tmp',name);if(!session)await sleep(30);}
 assert(session,'C-c d started a private server while native editor stayed open');const url=fs.readFileSync(path.join(session,'ready'),'utf8').trim();
 for(let i=0;i<100&&!fs.existsSync(launchLog);i++)await sleep(20);
 assert.equal(fs.readFileSync(launchLog,'utf8').trim(),url,'C-c d launches the browser command found on PATH');
 assert.equal(await (await fetch(url+'session')).text(),'Native original\n');
 if(conflict)await sleep(1200);
 let r=await fetch(url+'session',{method:'PUT',headers:{Origin:new URL(url).origin,'Content-Type':'application/x-chezweb-text'},body:'Browser replacement é\n'});assert.equal(r.status,200);
 assert.equal(fs.readFileSync(fixture,'utf8'),'Native original\n','browser handoff never writes the user document itself');
 assert.equal(await exited,0,fs.readFileSync(screen,'utf8').slice(-2000));
 if(conflict){assert.equal(fs.readFileSync(other,'utf8'),'Browser replacement é\n');assert.equal(fs.readFileSync(fixture,'utf8'),'local Native original\n');console.log('PASS concurrent native edits preserved; browser text saved separately from conflict buffer');}
 else{assert.equal(fs.readFileSync(fixture,'utf8'),'Browser replacement é\n');console.log('PASS C-c d keeps native terminal alive, imports browser save, explicit native save writes fixture');}
 assert(!fs.existsSync(session),'server and temporary handoff cleaned on native exit');
}
(async()=>{try{let cc=cp.spawnSync(process.env.CC||'cc',['-O2',path.join(root,'tests/pty-keys.c'),'-o',path.join(work,'pty-keys'),'-lutil']);if(cc.status!==0)cc=cp.spawnSync(process.env.CC||'cc',['-O2',path.join(root,'tests/pty-keys.c'),'-o',path.join(work,'pty-keys')]);assert.equal(cc.status,0,cc.stderr.toString());await run(false);await run(true);}finally{fs.rmSync(work,{recursive:true,force:true});}})().catch(e=>{console.error(e);process.exitCode=1;});
