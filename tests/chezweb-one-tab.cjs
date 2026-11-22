// Development only (playwright, Chrome).  One tab per file (21 November
// 2026): two tabs editing the same file lose work, because the second save
// replaces the first without a question.
//  1. C-c d opens no second tab while the first is open on the file; a
//     second tab on the same address shows why and starts no editor; once
//     the first closes (or reloads) the file opens again.
//  2. C-x C-f refuses a file of a granted folder that another tab has open,
//     even when the two tabs granted the folder separately; a different
//     file with the same name (another folder called docs) opens.
//  3. A save never writes over a change made on disk since the tab read
//     the file; the buffer keeps its text.
// Tabs of one Chrome profile share locks: here, pages of one context.
// Every file is disposable: a temporary home, and Chrome's private origin
// storage (OPFS) for the granted folders.
const {chromium}=require('playwright');
const http=require('http'),fs=require('fs'),os=require('os'),path=require('path'),cp=require('child_process'),assert=require('assert');
const root=path.resolve(__dirname,'..'),work=fs.mkdtempSync(path.join(os.tmpdir(),'chezweb-one-tab-'));
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function until(pred,message,tries=400){for(let i=0;i<tries;i++){if(await pred())return;await sleep(25);}throw Error(message);}
let browser,proc,server;
(async()=>{try{
 browser=await chromium.launch({channel:'chrome',headless:true});
 const screenText=p=>p.locator('#screen-text').textContent();
 const wait=(p,s)=>p.waitForFunction(s=>document.getElementById('screen-text').textContent.includes(s),s,{timeout:20000});
 const waitNotice=(p,s)=>p.waitForFunction(s=>document.getElementById('notice').textContent.includes(s),s,{timeout:20000});

 // ---- 1. the file of C-c d ----
 const cc=cp.spawnSync(process.env.CC||'cc',['-O2',path.join(root,'tests/pty-keys.c'),'-o',path.join(work,'pty')]);assert.equal(cc.status,0);
 const bin=path.join(work,'bin');fs.mkdirSync(bin);
 fs.writeFileSync(path.join(bin,'browser-fixture'),'#!/bin/sh\nprintf "%s\\n" "$1" >> "$CHEZWEB_TEST_URL"\n',{mode:0o755});
 const file=path.join(work,'nia.md'),urls=path.join(work,'urls'),screen=path.join(work,'screen');
 const second=path.join(work,'second'),third=path.join(work,'third'),finish=path.join(work,'finish');
 fs.writeFileSync(file,'ORIGINAL\n');
 fs.writeFileSync(path.join(work,'keys'),'await-screen C-h help\nkeys ^Cd\nawait-file '+second+'\nkeys ^Cd\nawait-file '+third+'\nkeys ^Cd\nawait-file '+finish+'\nkeys ^X^C\n');
 proc=cp.spawn(path.join(work,'pty'),[path.join(work,'keys'),'120',screen,path.join(root,'chezweb'),file],{cwd:root,env:{...process.env,HOME:work,CHEZEMAX_NO_INIT:'1',CHEZWEB_BROWSER:'browser-fixture',CHEZWEB_TEST_URL:urls,PATH:bin+path.delimiter+process.env.PATH}});
 const exited=new Promise(r=>proc.on('exit',r));
 const launches=()=>fs.existsSync(urls)?fs.readFileSync(urls,'utf8').trim().split('\n').filter(Boolean):[];
 await until(()=>launches().length===1,'C-c d did not open the browser');
 const url=launches()[0];
 const ctx=await browser.newContext();
 const p1=await ctx.newPage();await p1.goto(url);await wait(p1,'ORIGINAL');
 const p2=await ctx.newPage();await p2.goto(url);
 await p2.waitForFunction(()=>document.getElementById('starting').textContent.includes('is open in another Chezweb tab'),null,{timeout:20000});
 assert.equal(await screenText(p2),'','the refused tab must start no editor');
 await waitNotice(p1,'Another tab asked to open');
 console.log('PASS a second tab on the file of C-c d shows why and starts no editor; the first tab is told');
 fs.writeFileSync(second,'go');
 await until(()=>fs.readFileSync(screen,'utf8').includes('already open in Chrome'),'C-c d did not refuse');
 await sleep(500);assert.equal(launches().length,1,'C-c d opened a second tab');
 console.log('PASS C-c d opens no second tab while the first is open on the file');
 await p2.close();await p1.close();
 fs.writeFileSync(third,'go');
 await until(()=>launches().length===2,'C-c d did not open the browser after the tab closed');
 const p3=await ctx.newPage();await p3.goto(url);await wait(p3,'ORIGINAL');
 await p3.reload();await wait(p3,'ORIGINAL');
 console.log('PASS once the tab closes, C-c d opens the file again, and a reload keeps it');
 await p3.close();fs.writeFileSync(finish,'done');assert.equal(await exited,0);proc=null;

 // ---- 2 and 3. files of granted folders ----
 server=http.createServer((q,r)=>{if(q.url==='/session'){r.end('Start buffer\n');return;}if(q.url==='/name'){r.end('start.md');return;}let name=q.url==='/'?'Chezweb.html':q.url.slice(1);if(!['Chezweb.html','build/chezweb.js','build/chezweb.wasm'].includes(name)){r.writeHead(404);r.end();return;}r.setHeader('Content-Type',name.endsWith('.wasm')?'application/wasm':name.endsWith('.js')?'text/javascript':'text/html');r.end(fs.readFileSync(path.join(root,name)));});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const home='http://127.0.0.1:'+server.address().port+'/';
 const ctx2=await browser.newContext();
 // showDirectoryPicker gives a folder of the origin's private storage: a
 // real FileSystemDirectoryHandle, without a dialog.
 await ctx2.addInitScript(()=>{window.showDirectoryPicker=async()=>{let d=await navigator.storage.getDirectory();for(const n of (window.pickPath||'docs').split('/'))d=await d.getDirectoryHandle(n);return d;};});
 const opfs=(p,op)=>p.evaluate(async op=>{
  async function at(parts,create){let d=await navigator.storage.getDirectory();for(const n of parts.slice(0,-1))d=await d.getDirectoryHandle(n,{create});return d.getFileHandle(parts[parts.length-1],{create});}
  const h=await at(op.path.split('/'),!!op.write);
  if(op.write!==undefined){const w=await h.createWritable();await w.write(op.write);await w.close();return null;}
  return await (await h.getFile()).text();
 },op);
 const tab=async pick=>{const p=await ctx2.newPage();if(pick)await p.addInitScript(p=>{window.pickPath=p;},pick);await p.goto(home);await wait(p,'Start buffer');return p;};
 const find=async(p,name)=>{for(const k of ['Control+x','Control+f'])await p.keyboard.press(k);await wait(p,'Find');await p.keyboard.press('Control+a');await p.keyboard.press('Control+k');await p.keyboard.insertText('~/doc');await p.keyboard.press('Tab');await wait(p,'~/docs/');await p.keyboard.insertText(name);await p.keyboard.press('Enter');};
 const q1=await tab();
 await opfs(q1,{path:'docs/a.md',write:'Alpha in docs\n'});await opfs(q1,{path:'docs/b.md',write:'Beta in docs\n'});await opfs(q1,{path:'other/docs/a.md',write:'Alpha elsewhere\n'});
 await find(q1,'a.md');await wait(q1,'Alpha in docs');
 const q2=await tab();
 await find(q2,'a.md');await waitNotice(q2,'is open in another Chezweb tab');
 assert(!(await screenText(q2)).includes('Alpha in docs'),'the refused file must not open');
 console.log('PASS C-x C-f refuses a file another tab has open, through a separate grant of its folder');
 const q3=await tab('other/docs');
 await find(q3,'a.md');await wait(q3,'Alpha elsewhere');
 console.log('PASS another file of the same name, in another folder called docs, opens');
 await find(q2,'b.md');await wait(q2,'Beta in docs');
 await opfs(q1,{path:'docs/b.md',write:'Changed elsewhere, longer\n'});
 for(const k of ['Escape','Shift+Period'])await q2.keyboard.press(k);await q2.keyboard.insertText('Tab two edit ');
 await q2.keyboard.press('Control+x');await q2.keyboard.press('Control+s');
 await waitNotice(q2,'changed on disk since this tab read it');
 assert.equal(await opfs(q1,{path:'docs/b.md'}),'Changed elsewhere, longer\n');
 assert((await screenText(q2)).includes('Tab two edit'),'the buffer keeps its text');
 console.log('PASS a save does not write over a change made on disk since the tab read the file; the text stays');
 await q1.close();
 await find(q2,'a.md');await wait(q2,'Alpha in docs');
 for(const k of ['Escape','Shift+Period'])await q2.keyboard.press(k);await q2.keyboard.insertText('Saved by tab two');
 await q2.keyboard.press('Control+x');await q2.keyboard.press('Control+s');
 // read again while Chrome still holds the file for the write
 await until(async()=>(await opfs(q2,{path:'docs/a.md'}).catch(()=>'')).includes('Saved by tab two'),'the save after the other tab closed did not write');
 console.log('PASS when the other tab closes, the file opens and saves here');
}catch(e){console.error(e);process.exitCode=1;}
finally{if(proc)proc.kill('SIGTERM');if(server)server.close();if(browser)await browser.close();fs.rmSync(work,{recursive:true,force:true});}})();
