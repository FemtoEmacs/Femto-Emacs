// Development only: real Chrome + native editor, disposable files.  The
// logbook's 9 November 2026 complaint, end to end: the native buffer is
// edited after C-c d, so the browser's C-x C-s is refused and says why;
// M-x native-window-update puts the browser text in the native buffer and
// the next C-x C-s in the browser writes the file.
const {chromium}=require('playwright');
const fs=require('fs'),os=require('os'),path=require('path'),cp=require('child_process'),assert=require('assert');
const root=path.resolve(__dirname,'..'),work=fs.mkdtempSync(path.join(os.tmpdir(),'chezweb-native-update-page-'));
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{let browser,proc,exit;const finish=path.join(work,'finish'),trigger=path.join(work,'trigger'),screen=path.join(work,'screen');try{
 const bin=path.join(work,'bin');fs.mkdirSync(bin);
 fs.writeFileSync(path.join(bin,'fixture-browser'),'#!/bin/sh\nprintf "%s\\n" "$1" > "$CHEZWEB_TEST_URL"\n',{mode:0o755});
 const file=path.join(work,'orgnotes.md'),urlFile=path.join(work,'url');fs.writeFileSync(file,'Chezweb original\n');
 fs.writeFileSync(path.join(work,'keys'),'await-screen Chezweb original\nkeys ^Cd\nawait-file '+trigger+'\nkeys NATIVE \nkeys \\e:(quote NATIVE-READY)\\r\nawait-file '+finish+'\nkeys ^X^Cy\n');
 const cc=cp.spawnSync(process.env.CC||'cc',['-O2',path.join(root,'tests/pty-keys.c'),'-o',path.join(work,'pty')]);assert.equal(cc.status,0);
 proc=cp.spawn(path.join(work,'pty'),[path.join(work,'keys'),'90',screen,path.join(root,'chezweb'),file],{cwd:root,env:{...process.env,HOME:work,CHEZEMAX_NO_INIT:'1',CHEZWEB_BROWSER:'fixture-browser',CHEZWEB_TEST_URL:urlFile,PATH:bin+path.delimiter+process.env.PATH}});
 exit=new Promise(r=>proc.on('exit',r));for(let i=0;i<400&&!fs.existsSync(urlFile);i++)await sleep(30);assert(fs.existsSync(urlFile),'native browser launch');const url=fs.readFileSync(urlFile,'utf8').trim();
 browser=await chromium.launch({channel:'chrome',headless:true});const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 const wait=s=>page.waitForFunction(s=>document.getElementById('screen-text').textContent.includes(s),s,{timeout:15000});
 const notice=s=>page.waitForFunction(s=>document.getElementById('notice').textContent.includes(s),s,{timeout:15000});
 const seq=async(...keys)=>{for(const key of keys)await page.keyboard.press(key);};
 const save=async()=>{await page.evaluate(()=>{window.previousSave=Module.chezwebSave;});await seq('Control+x','Control+s');await page.waitForFunction(()=>Module.chezwebSave!==window.previousSave);return page.evaluate(()=>Module.chezwebSave);};
 await page.goto(url);await wait('Chezweb original');
 fs.writeFileSync(trigger,'edit');for(let i=0;i<400&&!fs.readFileSync(screen,'utf8').includes('NATIVE-READY');i++)await sleep(25);
 assert(fs.readFileSync(screen,'utf8').includes('NATIVE-READY'),'native edit');
 await seq('Control+a');await page.keyboard.insertText('Browser ');await wait('Browser Chezweb original');
 assert.equal(await save(),false);await notice('edited after C-c d');await notice('native-window-update');
 assert.equal(fs.readFileSync(file,'utf8'),'Chezweb original\n');
 console.log('PASS the refused save says the native buffer was edited, and how to go on');
 await page.evaluate(()=>Module.browsered.queueScheme('(native-window-update)'));await notice('Native buffer updated from the browser');await notice('*native-1*');
 assert.equal(fs.readFileSync(file,'utf8'),'Chezweb original\n','the update writes no file');
 assert.equal(await save(),true);assert.equal(fs.readFileSync(file,'utf8'),'Browser Chezweb original\n');
 console.log('PASS M-x native-window-update, then C-x C-s in the browser saves the file');
 assert.deepEqual(errors,[]);
 fs.writeFileSync(finish,'done');assert.equal(await exit,0);
}finally{try{fs.writeFileSync(finish,'done');}catch(_){}if(browser)await browser.close();if(proc&&proc.exitCode===null){await Promise.race([exit,sleep(1500)]);if(proc.exitCode===null)proc.kill('SIGTERM');}fs.rmSync(work,{recursive:true,force:true});}})().catch(e=>{console.error(e);process.exitCode=1;});
