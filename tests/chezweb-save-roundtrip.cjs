// Real Chrome + native editor. Every file and folder grant is disposable.
const {chromium}=require('playwright');
const fs=require('fs'),os=require('os'),path=require('path'),cp=require('child_process'),assert=require('assert');
const root=path.resolve(__dirname,'..'),work=fs.mkdtempSync(path.join(os.tmpdir(),'chezweb-save-roundtrip-'));
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{let browser,proc,exit;const finish=path.join(work,'finish');try{
 const bin=path.join(work,'bin');fs.mkdirSync(bin);fs.mkdirSync(path.join(work,'docs'));fs.mkdirSync(path.join(work,'other'));
 fs.writeFileSync(path.join(bin,'fixture-browser'),'#!/bin/sh\nprintf "%s\\n" "$1" > "$CHEZWEB_TEST_URL"\n',{mode:0o755});
 const file=path.join(work,'docs','chezweb-nia.md'),other=path.join(work,'other','chezweb-nia.md'),urlFile=path.join(work,'url');fs.writeFileSync(file,'Chezweb original\n');fs.writeFileSync(other,'Unrelated local file\n');
 fs.writeFileSync(path.join(work,'keys'),'await-screen Chezweb original\nkeys ^Cd\nawait-file '+finish+'\nkeys ^X^C\n');
 const cc=cp.spawnSync(process.env.CC||'cc',['-O2',path.join(root,'tests/pty-keys.c'),'-o',path.join(work,'pty')]);assert.equal(cc.status,0);
 proc=cp.spawn(path.join(work,'pty'),[path.join(work,'keys'),'90',path.join(work,'screen'),path.join(root,'chezweb'),file],{cwd:root,env:{...process.env,HOME:work,CHEZEMAX_NO_INIT:'1',CHEZWEB_BROWSER:'fixture-browser',CHEZWEB_TEST_URL:urlFile,PATH:bin+path.delimiter+process.env.PATH}});
 exit=new Promise(r=>proc.on('exit',r));for(let i=0;i<400&&!fs.existsSync(urlFile);i++)await sleep(30);assert(fs.existsSync(urlFile),'native browser launch');const url=fs.readFileSync(urlFile,'utf8').trim();
 browser=await chromium.launch({channel:'chrome',headless:true});const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.exposeFunction('fixtureRead',id=>fs.readFileSync(id==='source'?file:other,'utf8'));
 await page.exposeFunction('fixtureWrite',(id,text)=>fs.writeFileSync(id==='source'?file:other,text));
 await page.addInitScript(()=>{
  window.localWrites=[];window.denyLocal=false;
  function handle(id){return {id,kind:'file',name:'chezweb-nia.md',isSameEntry:async h=>h.id===id,getFile:async()=>new File([await fixtureRead(id)],'chezweb-nia.md',{lastModified:123}),createWritable:async()=>{
   if(denyLocal)throw new DOMException('Permission denied by test','NotAllowedError');
   return {write:async bytes=>{const text=new TextDecoder().decode(bytes);await fixtureWrite(id,text);localWrites.push([id,text]);},close:async()=>{}};
  }};}
  const source=handle('source'),other=handle('other');
  window.showOpenFilePicker=async()=>[other];
  window.showDirectoryPicker=async()=>({kind:'directory',name:'docs',async *values(){yield source;},getFileHandle:async()=>source});
 });
 const wait=s=>page.waitForFunction(s=>document.getElementById('screen-text').textContent.includes(s),s,{timeout:15000});
 const seq=async(...keys)=>{for(const key of keys)await page.keyboard.press(key);};
 const save=async()=>{await page.evaluate(()=>{window.previousSave=Module.chezwebSave;});await seq('Control+x','Control+s');await page.waitForFunction(()=>Module.chezwebSave!==window.previousSave);return page.evaluate(()=>Module.chezwebSave);};
 const evaluate=async(code,marker)=>{await page.evaluate(s=>Module.browsered.queueScheme('(message (value->string '+s+'))'),code);await wait(marker);};
 await page.goto(url);await wait('Chezweb original');
 await page.getByRole('button',{name:'Choose folder'}).click();await page.getByText('Current directory: ~/docs',{exact:false}).waitFor();
 assert.equal(fs.readFileSync(file,'utf8'),'Chezweb original\n','choosing a folder writes nothing');
 await seq('Control+a');await page.keyboard.insertText('Browser é🙂 ');await wait('Browser é🙂 Chezweb original');assert.equal(await save(),true);
 let saved='Browser é🙂 Chezweb original\n';assert.equal(fs.readFileSync(file,'utf8'),saved);assert.equal(await page.evaluate(()=>localWrites.length),0,'folder selection must not retarget the native snapshot');
 console.log('PASS choosing docs then saving the native snapshot writes the original disk file with no native key');
 fs.chmodSync(file,0o444);await seq('Escape','Shift+Period');await page.keyboard.insertText(' retry');await wait(' retry');assert.equal(await save(),false);
 assert.equal(fs.readFileSync(file,'utf8'),saved);await evaluate('(if (buffer-modified-p) (quote SAVE-STILL-DIRTY) (quote WRONG-CLEAN))','SAVE-STILL-DIRTY');
 await evaluate('(list (quote SCHEME-SAVE-FAIL) (save-buffer (get-buffer-name)) (buffer-modified-p))','(SCHEME-SAVE-FAIL #f #t)');
 fs.chmodSync(file,0o644);assert.equal(await save(),true);saved='Browser é🙂 Chezweb original\n retry';assert.equal(fs.readFileSync(file,'utf8'),saved);
 console.log('PASS failed native writes preserve the browser dirty flag; retry persists and acknowledges');
 await seq('Control+x','Control+f');await wait('Find');await seq('Control+a','Control+k');await page.keyboard.insertText('~/docs/chezweb-nia.md');await seq('Enter');await wait(' retry');
 await seq('Escape','Shift+Period');await page.keyboard.insertText(' direct');await wait(' direct');await page.evaluate(()=>{denyLocal=true;});assert.equal(await save(),false);assert.equal(fs.readFileSync(file,'utf8'),saved);
 await evaluate('(if (buffer-modified-p) (quote LOCAL-STILL-DIRTY) (quote WRONG-CLEAN))','LOCAL-STILL-DIRTY');
 await page.evaluate(()=>{denyLocal=false;});assert.equal(await save(),true);saved+=' direct';assert.equal(fs.readFileSync(file,'utf8'),saved);
 for(let i=0;i<100;i++){if(await (await fetch(url+'snapshot')).text()===saved)break;await sleep(30);}
 assert.equal(await (await fetch(url+'snapshot')).text(),saved,'direct local saves must refresh the native counterpart');
 console.log('PASS granted-folder saves write once, fail honestly, and refresh the same native file');
 await page.getByRole('button',{name:'Open local file'}).click();await wait('Unrelated local file');await seq('Escape','Shift+Period');await page.keyboard.insertText(' OTHER');assert.equal(await save(),true);
 assert.equal(fs.readFileSync(other,'utf8'),'Unrelated local file\n OTHER');assert.equal(fs.readFileSync(file,'utf8'),saved,'same-basename picked file must not overwrite the native original');
 console.log('PASS picking an unrelated file with the same basename has its own save destination');
 await evaluate('(begin (select-buffer "chezweb-nia.md") (quote ROOT-SELECTED))','ROOT-SELECTED');await wait(' retry');
 await seq('Escape','Shift+Period');await page.keyboard.insertText(' STALE');assert.equal(await save(),false);assert.equal(fs.readFileSync(file,'utf8'),saved);
 await evaluate('(if (buffer-modified-p) (quote STALE-STILL-DIRTY) (quote WRONG-CLEAN))','STALE-STILL-DIRTY');
 console.log('PASS an older snapshot cannot overwrite a newer direct save and remains unsaved');
 assert.deepEqual(errors,[]);
 // A fresh snapshot tests the exact Save-and-quit workflow, including any
 // pending asynchronous receipt. window.close is observable in a test tab.
 const fresh=await browser.newPage();await fresh.goto(url);await fresh.waitForFunction(()=>document.getElementById('screen-text').textContent.includes(' direct'));
 await fresh.evaluate(()=>{window.close=()=>{window.saveClosed=true;};});await fresh.keyboard.press('Escape');await fresh.keyboard.press('Shift+Period');await fresh.keyboard.insertText(' quit');
 await fresh.keyboard.press('Control+x');await fresh.keyboard.press('Control+s');await fresh.keyboard.press('Control+x');await fresh.keyboard.press('Control+c');
 await fresh.waitForFunction(()=>window.saveClosed);assert.equal(fs.readFileSync(file,'utf8'),saved+' quit');
 fs.writeFileSync(finish,'done');assert.equal(await exit,0,'native source must already be clean');
 console.log('PASS Save then quit waits for disk confirmation and leaves the idle native file clean');
}finally{
 if(proc&&proc.exitCode===null){try{fs.writeFileSync(finish,'done');}catch(_){}await Promise.race([exit||sleep(0),sleep(1500)]);if(proc.exitCode===null)proc.kill('SIGTERM');}
 if(browser)await browser.close();fs.rmSync(work,{recursive:true,force:true});
}})().catch(e=>{console.error(e);process.exitCode=1;});
