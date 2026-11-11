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
  async function hoverButton(label,offset=1) {
   const pos=await page.evaluate(({label,offset})=>{
    const lines=document.getElementById('screen-text').textContent.split('\n'),needle='['+label+']',row=lines.findIndex(s=>s.includes(needle));
    if(row<0)throw Error('Missing button '+label);
    const col=lines[row].indexOf(needle)+offset,g=Module.browsered.layerGeometry(),box=document.getElementById('screen').getBoundingClientRect();
    window.hoverPaint=0;
    if(window.hoverObserver)window.hoverObserver.disconnect();
    window.hoverObserver=new MutationObserver(()=>window.hoverPaint++);
    window.hoverObserver.observe(document.getElementById('screen-text'),{childList:true});
    return {x:box.left+g.pad+(col+.5)*g.cw,y:g.top+g.pad+(row+.5)*g.ch};
   },{label,offset});
   await page.mouse.move(pos.x,pos.y);
   await page.waitForFunction(()=>window.hoverPaint>0);
  }
  await hoverButton('SAVE');await wait('Button runs save-buffer (C-x C-s)');
  // Staying over the same button used to clear its hint on the next cell.
  for(const offset of [2,3,4]) {
   await hoverButton('SAVE',offset);
   assert((await page.locator('#screen-text').textContent()).includes('Button runs save-buffer (C-x C-s)'), 'SAVE hint disappeared within its button');
  }
  for(const [label,command] of [['UNDO','undo'],['Select','menu-select'],['MORE','more-menu'],['QUIT','exit'],['?','help-menu'],['SAVE','save-buffer']]) {
   await hoverButton(label);
   await wait('Button runs '+command);
  }
  await evaluate('(quote REPLACED-HINT)','REPLACED-HINT');
  await hoverButton('SAVE',2);await wait('Button runs save-buffer (C-x C-s)');
  await evaluate('(list (quote HOVER-SAFE) (point) (window-count) (string=? (buffer-string) (file-contents (buffer-filename))))','(HOVER-SAFE 0 1 #t)');
  assert.deepStrictEqual(errors,[]);assert.strictEqual(writes,0);
  console.log('PASS all browser button hints, movement within SAVE, and hint recovery without edits');
 } finally {await browser.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;server.close();});
