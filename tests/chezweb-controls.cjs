// Regression: repeated real key events through Chrome and the native C modes.
const {chromium}=require('playwright');
const http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');
const fixture=Array.from({length:1829},(_,i)=>`line ${String(i+1).padStart(4,'0')}`).join('\n')+'\n';
let writes=0;
const server=http.createServer((q,r)=>{
 if(q.url==='/session'){if(q.method!=='GET'){writes++;q.resume();r.end('ok');}else r.end(fixture);return;}
 if(q.url==='/name'){r.end('native-read.md');return;}
 const f=q.url==='/'?'Chezweb.html':q.url.slice(1);
 if(!['Chezweb.html','build/chezweb.js','build/chezweb.wasm'].includes(f)){r.writeHead(404);r.end();return;}
 r.setHeader('Content-Type',f.endsWith('.wasm')?'application/wasm':f.endsWith('.js')?'text/javascript':'text/html');
 r.end(fs.readFileSync(path.join(root,f)));
});
(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const browser=await chromium.launch({channel:'chrome',headless:true});
 try {
  const page=await browser.newPage({viewport:{width:1100,height:740}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  const wait=async marker=>{try{await page.waitForFunction(s=>document.getElementById('screen-text').textContent.includes(s),marker,{timeout:30000});}catch(e){console.error(await page.locator('#screen-text').textContent());throw e;}};
  const evaluate=async(code,marker)=>{await page.evaluate(s=>Module.browsered.queueScheme('(message (value->string '+s+'))'),code);await wait(marker);};
  await page.goto('http://127.0.0.1:'+server.address().port);await wait('line 0001');
  await evaluate('(list (quote EMPTY-READY) (null? *kill-ring*))','(EMPTY-READY #t)');
  await page.keyboard.press('Control+c');await page.keyboard.press('k');await wait('The kill ring is empty');
  await evaluate('(list (quote EMPTY-RETURNED) (get-buffer-name) (window-count))','(EMPTY-RETURNED "native-read.md" 1)');
  console.log('PASS empty kill ring returns without consuming the next command');
  await evaluate('(begin (push-kill "copied sample") (quote RING-READY))','RING-READY');
  await page.keyboard.press('Control+c');await page.keyboard.press('k');await wait('kill item 1');
  await page.keyboard.press('c');await wait('copied to clipboard');await page.keyboard.press('x');
  await evaluate('(list (quote RING-RETURNED) (get-buffer-name) (string=? (get-clipboard) "copied sample"))','(RING-RETURNED "native-read.md" #t)');
  console.log('PASS populated kill ring still copies and exits');
  await evaluate('(begin (split-window) (list (quote SPLIT-READY) (window-rows)))','(SPLIT-READY ');
  const before=Number((await page.locator('#screen-text').textContent()).match(/SPLIT-READY (\d+)/)[1]);
  await page.keyboard.press('Control+x');await page.keyboard.press('w');
  await evaluate('(list (quote ENLARGED) (window-rows))','(ENLARGED '+(before+1)+')');
  console.log('PASS C-x w enlarges the selected window');
  await page.keyboard.insertText('Z');await page.keyboard.press('Control+/');
  await evaluate('(list (quote UNDONE) (= (buffer-size) 18290))','(UNDONE #t)');
  await page.keyboard.press('Control+Backslash');
  await evaluate('(list (quote REDONE) (= (buffer-size) 18291) (= (buffer-get 0) 90))','(REDONE #t #t)');
  await page.keyboard.press('Control+/');
  console.log('PASS C-backslash redoes the change undone by C-slash');
  await evaluate('(begin (delete-other-windows) (quote HOVER-READY))','HOVER-READY');
  const pos=await page.evaluate(()=>{
   const lines=document.getElementById('screen-text').textContent.split('\n'),row=lines.findIndex(s=>s.includes('[SAVE]')),col=lines[row].indexOf('[SAVE]')+2;
   const canvas=document.getElementById('screen'),box=canvas.getBoundingClientRect(),ctx=canvas.getContext('2d');ctx.font='15px Menlo,Consolas,monospace';
   return {x:box.left+4+(col+0.5)*ctx.measureText('MMMMMMMMMM').width/10,y:box.top+4+(row+0.5)*21};
  });
  await page.mouse.move(pos.x,pos.y);await wait('Button runs save-buffer (C-x C-s)');
  await evaluate('(list (quote HOVER-SAFE) (point) (window-count) (string=? (buffer-string) (file-contents (buffer-filename))))','(HOVER-SAFE 0 1 #t)');
  assert.deepStrictEqual(errors,[]);assert.strictEqual(writes,0);
  console.log('PASS passive SAVE hover describes its command without clicking or editing');
 } finally {await browser.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;server.close();});
