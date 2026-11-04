// Development-only automation: the installed Google Chrome, never Edge.
const {chromium}=require('playwright');
const http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');let saved='',calls=[];
const server=http.createServer((q,r)=>{
 calls.push(q.url);
 if(q.url==='/session'){if(q.method==='PUT'){let body='';q.on('data',b=>body+=b);q.on('end',()=>{saved=body;r.end('ok');});}else r.end('A Chezweb test.\nSecond line.\n');return;}
 if(q.url==='/name'){r.end('test.md');return;}
 let file=q.url==='/'?'Chezweb.html':q.url.slice(1);
 if(!['Chezweb.html','build/chezweb.js','build/chezweb.wasm'].includes(file)){r.writeHead(404);r.end();return;}
 r.setHeader('Content-Type',file.endsWith('.wasm')?'application/wasm':file.endsWith('.js')?'text/javascript':'text/html');r.end(fs.readFileSync(path.join(root,file)));
});
(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await chromium.launch({channel:'chrome',headless:true});
 try{const opener=await browser.newPage({viewport:{width:1100,height:740}});
 const opened=opener.waitForEvent('popup');await opener.evaluate(()=>window.open('about:blank'));const page=await opened,errors=[];
 await page.addInitScript(()=>{window.fixtureWrites=[];window.showOpenFilePicker=async()=>[{getFile:async()=>new File(['Local picker fixture\n'],'picked.md'),createWritable:async()=>({write:async b=>window.fixtureWrites.push(new TextDecoder().decode(b)),close:async()=>{}})}];});page.on('pageerror',e=>errors.push(e.stack));
 const text=()=>page.locator('#screen-text').textContent();
 const wait=async s=>{try{await page.waitForFunction(s=>document.getElementById('screen-text').textContent.includes(s),s,{timeout:15000});}catch(e){console.error('SCREEN:',await text(),'ERRORS:',errors);await page.screenshot({path:'/private/tmp/chezweb-failed.png'});throw e;}};
 const seq=async(...keys)=>{for(const key of keys)await page.keyboard.press(key);};
 const type=async s=>page.keyboard.insertText(s);
 await page.goto('http://127.0.0.1:'+server.address().port);await wait('A Chezweb test.');
 await seq('Alt+x');await type('script-installer');await seq('Enter');await wait('run script-installer in the terminal/GUI window');
 assert.equal(saved,'');assert(!(await page.evaluate(()=>FS.analyzePath('/home/web_user/.chezemax/users').exists)));
 console.log('PASS browser script-installer gives native-window guidance without saving or a virtual installation');
 await seq('Control+c','k');await wait('The kill ring is empty');
 await type('Empty menu returned');await wait('Empty menu returned');
 await seq('Control+a','Control+k');
 for(const exit of ['q','Control+g']){
  await seq('Control+c','k');await wait('q/x/C-g exits');
  await seq(exit);await page.waitForFunction(()=>!document.getElementById('screen-text').textContent.includes('q/x/C-g exits'));
 }
 console.log('PASS empty kill ring returns immediately; populated menu exits with q and C-g');
 await seq('Control+x','2');await page.waitForFunction(()=>document.getElementById('screen-text').textContent.split('\n').filter(s=>s.includes('[?]')).length===2);
 const modes=await page.evaluate(()=>document.getElementById('screen-text').textContent.split('\n').map((s,i)=>s.includes('[?]')?i:-1).filter(i=>i>=0));
 await seq('Control+Backslash');await page.waitForFunction(before=>{
  const after=document.getElementById('screen-text').textContent.split('\n').map((s,i)=>s.includes('[?]')?i:-1).filter(i=>i>=0);
  return after.length===2&&after[0]!==before[0];
 },modes);console.log('PASS C-backslash enlarges the selected browser window');
 await page.reload();await wait('A Chezweb test.');
 assert(await page.evaluate(()=>typeof WebAssembly.Suspending==='function'));console.log('PASS real Chrome JSPI, unchanged compiled editor startup');
 await seq('Control+x','Control+f');await wait('Find');await seq('Control+a','Control+k');await type('/home/web_user/other.txt');await seq('Enter');await type('Other buffer marker');await wait('Other buffer marker');await seq('Control+x','Control+s');
 await seq('Control+x','b');await wait('Switch to buffer');await type('test.md');await seq('Enter');await wait('A Chezweb test.');console.log('PASS C-x b prompt suspends through compiled Scheme and selects a buffer');
 await seq('Control+x','Control+b');await wait('Size');await seq('ArrowDown','ArrowUp','Enter');await page.waitForTimeout(150);assert(!(await text()).includes('CO  Size Buffer'));console.log('PASS C-x C-b modal menu: navigation and selection');
 // Select the source reliably before the remaining tests.
 await seq('Control+x','b');await wait('Switch to buffer');await type('test.md');await seq('Enter');await wait('A Chezweb test.');
 let pos=await page.evaluate(()=>{let ls=document.getElementById('screen-text').textContent.split('\n'),r=ls.findIndex(s=>s.includes('[?]')),c=ls[r].indexOf('[?]')+1;let ctx=document.getElementById('screen').getContext('2d');ctx.font='15px Menlo,Consolas,monospace';return {x:4+(c+.5)*ctx.measureText('MMMMMMMMMM').width/10,y:document.getElementById('screen').getBoundingClientRect().top+4+r*21+10};});
 await page.mouse.click(pos.x,pos.y);await wait('Keybindings');await type('2');await wait('terminal or SDL');console.log('PASS [?] click, compiled modal Help menu and ChatGPT guidance');
 await seq('Control+c','g');await wait('No AI login');await seq('Control+c','r');await wait('No AI login');
 await seq('Alt+x');await type('help-menu');await seq('Enter');await wait('Keybindings');await type('3');await wait('terminal or SDL');console.log('PASS Codex/Claude keyboard and Help paths use native-window advice');
 await seq('Control+x','Control+f');await wait('Find');await seq('Control+a','Control+k');await type('/home/web_user/new.txt');await seq('Enter');await type('Disposable new file');await wait('Disposable new file');
 await seq('Control+x','Control+w');await page.waitForTimeout(100);await seq('Control+a','Control+k');await type('/home/web_user/renamed.txt');await seq('Enter');await wait('renamed.txt');console.log('PASS file prompts and Save As through nested compiled frames');
 await seq('Control+x','b');await wait('Switch to buffer');await type('test.md');await seq('Enter');await wait('A Chezweb test.');await seq('Escape','Shift+Period');await type('Explicit browser save.');assert.strictEqual(saved,'');await seq('Control+x','Control+s');await page.waitForFunction(()=>!!Module.chezwebSave);await page.evaluate(()=>Module.chezwebSave);assert(saved.includes('Explicit browser save.'));console.log('PASS explicit save handoff; typing alone never sends a save');
 await page.getByRole('button',{name:'Open local file'}).click();await wait('Local picker fixture');await page.getByRole('button',{name:'Open local file'}).click();await page.waitForTimeout(100);assert.equal(await page.evaluate(()=>fixtureWrites.length),0);await seq('Escape','Shift+Period');await type('Explicit local save');await wait('Explicit local save');await seq('Control+x','Control+s');await page.waitForFunction(()=>fixtureWrites.length===1);await page.evaluate(()=>Module.chezwebSave);assert.equal(await page.evaluate(()=>fixtureWrites.length),1);assert((await page.evaluate(()=>fixtureWrites[0])).includes('Explicit local save'));console.log('PASS local file picker: opening/reopening writes nothing; explicit Save writes once');
 await seq('Escape','Shift+Semicolon');await wait('Eval');await type('(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2))))) (fib 25)');await seq('Enter');await wait('75025');console.log('PASS compiled Scheme evaluation in Chrome, with retained compiler reused after file opening');
 assert(!calls.some(s=>/codex|claude|api|shell/.test(s)));assert.deepStrictEqual(errors,[]);await page.screenshot({path:'/private/tmp/chezweb-chrome-tested.png'});
 // A pending explicit save must finish before the tab is closed.
 await page.evaluate(()=>{Module.chezwebSave=new Promise(r=>window.finishQuitSave=r);});
 await seq('Control+x','Control+c');await page.waitForTimeout(100);assert(!page.isClosed());
 const closed=page.waitForEvent('close');await page.evaluate(()=>window.finishQuitSave());try{await closed;}catch(e){console.error("QUIT SCREEN:",await text(),"ERRORS:",errors);throw e;}
 assert(browser.isConnected());console.log('PASS C-x C-c waits for pending save and closes its tab only');
 const fallback=await browser.newPage();await fallback.goto('http://127.0.0.1:'+server.address().port);await fallback.waitForFunction(()=>document.getElementById('screen-text').textContent.includes('A Chezweb test.'));
 await fallback.evaluate(()=>{window.close=()=>{};});await fallback.keyboard.press('Control+x');await fallback.keyboard.press('Control+c');
 await fallback.getByText('You can close this tab.',{exact:false}).waitFor();await fallback.close();console.log('PASS blocked tab closure displays a clear fallback');
 const unsupported=await browser.newPage();await unsupported.addInitScript(()=>{Object.defineProperty(WebAssembly,'Suspending',{value:undefined});});await unsupported.goto('http://127.0.0.1:'+server.address().port);await unsupported.getByText('Chezweb requires Chrome with WebAssembly JSPI.',{exact:false}).waitFor();await unsupported.close();console.log('PASS unsupported browser shows a clear JSPI requirement');
 }finally{await browser.close();server.close();}
})().catch(e=>{console.error(e);server.close();process.exitCode=1;});
