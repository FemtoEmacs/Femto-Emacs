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
 try{
  for(const mode of ['read','vim'])for(const key of ['ArrowDown','Enter']){
   const page=await browser.newPage({viewport:{width:1100,height:740}}),errors=[];
   page.on('pageerror',e=>errors.push(e.message));
   const wait=async text=>{try{await page.waitForFunction(s=>document.getElementById('screen-text').textContent.includes(s),text,{timeout:60000});}catch(e){console.error(await page.locator('#screen-text').textContent());throw e;}};
   const evaluate=async(code,marker)=>{await page.evaluate(s=>Module.browsered.queueScheme("(message (value->string "+s+"))"),code);await wait(marker);};
   await page.goto('http://127.0.0.1:'+server.address().port);await wait('line 0001');
   if(mode==='read'&&key==='ArrowDown')await evaluate('(begin (command-boundary "fixture") (insert "X") (undo) (quote PREPARED))','PREPARED');
   if(mode==='read'){await page.keyboard.press('Control+x');await page.keyboard.press('Control+q');await wait(' READ');}
   else{await evaluate('(begin (vim-mode) (quote MODE-READY))','MODE-READY');}
   await page.evaluate(key=>{for(let i=0;i<1900;i++)document.dispatchEvent(new KeyboardEvent('keydown',{key,bubbles:true}));},key);
   await evaluate('(list (quote BROWSER-END) (line-number) (buffer-read-only?))','(BROWSER-END 1830 #t)');
   console.log(`PASS Chrome ${mode} ${key}: long-file navigation`);
   let screen=await page.locator('#screen-text').textContent();assert(!screen.includes('Compiled Scheme (word wrap)'));
   // Both copy modes must refuse all former Vim mutation commands.
   await page.evaluate(()=>{Module.browsered.sendText('ddxppuUoOaAIrRJ.:');});
   await page.keyboard.press('Control+r');await page.keyboard.press('Control+y');
   await evaluate('(list (quote PROTECTED) (string=? (buffer-string) (file-contents (buffer-filename))) (buffer-read-only?))','(PROTECTED #t #t)');
   // Selection/copy starts at the first byte and includes the cursor.
   await evaluate('(begin (goto-char 0) (quote COPY-READY))','COPY-READY');
   await page.evaluate(()=>Module.browsered.sendText('vlly'));
   await evaluate('(list (quote COPIED) (string=? (get-clipboard) "lin") (buffer-read-only?))','(COPIED #t #t)');
   if(mode==='read'&&key==='ArrowDown'){
    await evaluate('(let ((h (current-history))) (let ((done (undo-history-done h)) (undone (undo-history-undone h))) (undo) (redo) (list (quote UNDO-SAFE) (equal? done (undo-history-done h)) (equal? undone (undo-history-undone h)))))','(UNDO-SAFE #t #t)');
    await evaluate('(begin (select-buffer "*copy-other*") (list (quote SEPARATE) (buffer-read-only?)))','(SEPARATE #f)');
    await evaluate('(begin (select-buffer "native-read.md") (list (quote RESTORED) (buffer-read-only?)))','(RESTORED #t)');
    console.log('PASS Chrome read-mode state belongs to its buffer');
   }
   assert.deepStrictEqual(errors,[]);await page.close();
   console.log(`PASS Chrome ${mode} ${key}: 1829 lines, edit protection and visual copy`);
  }
  // Same page, same compiled module and GC heap across every traversal.
  const cumulative=await browser.newPage({viewport:{width:1100,height:740}}),cumulativeErrors=[];
  cumulative.on('pageerror',e=>cumulativeErrors.push(e.message));
  const waitCumulative=async marker=>cumulative.waitForFunction(s=>document.getElementById('screen-text').textContent.includes(s),marker,{timeout:60000});
  const evaluateCumulative=async(code,marker)=>{await cumulative.evaluate(s=>Module.browsered.queueScheme('(message (value->string '+s+'))'),code);await waitCumulative(marker);};
  await cumulative.goto('http://127.0.0.1:'+server.address().port);await waitCumulative('line 0001');
  for(let pass=1;pass<=4;pass++){
   if(pass%2)await evaluateCumulative('(begin (vim-mode) (quote VIM-READY))','VIM-READY');
   else{await cumulative.keyboard.press('Control+x');await cumulative.keyboard.press('Control+q');}
   if(pass>1)await cumulative.evaluate(()=>Module.browsered.sendText('gg'));
   await cumulative.evaluate(()=>{for(let i=0;i<1900;i++)document.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}));});
   await evaluateCumulative('(list (quote CUMULATIVE-'+pass+') (= (point) (buffer-size)) (buffer-read-only?))','(CUMULATIVE-'+pass+' #t #t)');
   assert(!(await cumulative.locator('#screen-text').textContent()).includes('Compiled Scheme (word wrap)'));
  }
  assert.deepStrictEqual(cumulativeErrors,[]);await cumulative.close();
  console.log('PASS Chrome four traversals and Vim/READ switches in one page');
  assert.strictEqual(writes,0);console.log('PASS navigation and copying never saved the source');
 }finally{await browser.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);server.close();process.exitCode=1;});
