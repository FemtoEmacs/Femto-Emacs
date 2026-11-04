// Development-only Chrome regression: help inspects the live bindings.
const {chromium}=require('playwright');
const http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');let saves=0;
const server=http.createServer((q,r)=>{
 if(q.url==='/session'){if(q.method==='PUT'){saves++;q.resume();q.on('end',()=>r.end('ok'));}else r.end('Command help fixture\n');return;}
 if(q.url==='/name')return r.end('help-test.txt');
 const f=q.url==='/'?'Chezweb.html':q.url.slice(1);
 if(!['Chezweb.html','build/chezweb.js','build/chezweb.wasm'].includes(f)){r.writeHead(404);return r.end();}
 r.setHeader('Content-Type',f.endsWith('.wasm')?'application/wasm':f.endsWith('.js')?'text/javascript':'text/html');r.end(fs.readFileSync(path.join(root,f)));
});
(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await chromium.launch({channel:'chrome',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1200,height:800}}),errors=[];page.on('pageerror',e=>errors.push(e.stack));
  const text=()=>page.locator('#screen-text').textContent();
  const wait=async s=>{try{await page.waitForFunction(s=>document.getElementById('screen-text').textContent.includes(s),s,{timeout:20000});}catch(e){console.error('Expected:',s,'SCREEN:',await text(),'ERRORS:',errors);throw e;}};
  const seq=async(...ks)=>{for(const k of ks)await page.keyboard.press(k);};
  const button=label=>page.evaluate(label=>{
   const lines=document.getElementById('screen-text').textContent.split('\n');const row=lines.findIndex(s=>s.includes('['+label+']'));
   if(row<0)throw Error('Missing button '+label);const col=lines[row].indexOf('['+label+']')+2,g=Module.browsered.layerGeometry();
   return {x:g.pad+(col+.5)*g.cw,y:g.top+g.pad+(row+.5)*g.ch};
  },label);
  await page.goto('http://127.0.0.1:'+server.address().port);await wait('Command help fixture');
  const save=await button('SAVE');await page.mouse.move(save.x,save.y);await wait('Button runs save-buffer (C-x C-s)');
  await page.mouse.move(save.x+2,save.y);await wait('Button runs save-buffer');assert.equal(saves,0);
  console.log('PASS hover names the resolved key command without saving');
  const more=await button('MORE');await page.mouse.move(more.x,more.y);await wait('Button runs more-menu');
  console.log('PASS hover names a direct Scheme command');
  await page.mouse.move(15,80);await seq('Control+x');await page.keyboard.insertText('?');await wait('Describe key or click a button');
  await page.mouse.click(save.x,save.y);await wait('Button runs save-buffer (C-x C-s)');assert.equal(saves,0);
  console.log('PASS C-x ? inspects a button without executing its action');
  await seq('Control+x');await page.keyboard.insertText('?');await wait('Describe key or click a button');await seq('Control+f');await wait('C-f runs forward-char');
  console.log('PASS keyboard inspection still resolves commands');
  await seq('Control+x');await page.keyboard.insertText('?');await wait('Describe key or click a button');
  await page.mouse.click(more.x,more.y);await wait('Button runs more-menu');assert(!(await text()).includes('Choose a number'));
  console.log('PASS inspection of a direct command does not open its menu');
  await page.evaluate(()=>Module.browsered.queueScheme('(global-set-key "C-x C-s" (quote forward-char))'));await page.waitForTimeout(100);
  await page.mouse.move(save.x,save.y);await wait('Button runs forward-char (C-x C-s)');assert.equal(saves,0);
  console.log('PASS button help follows live key rebinding');
  await page.evaluate(()=>Module.browsered.queueScheme('(global-unset-key "C-x C-s")'));await page.mouse.move(15,80);await page.waitForTimeout(50);
  await seq('Control+h');await wait('PRESS i');assert((await text()).includes('Command: help'));
  // Full buffer text, rather than just the visible rows, must include the
  // native binding and the description together. Search moves to that row.
  await seq('Control+s');await page.keyboard.insertText('Command: find-file');await seq('Enter');await wait('Command: find-file');
  console.log('PASS C-h lists key, actual command name and description');
  await seq('i');await wait('Command help fixture');
  await seq('Control+s');await page.keyboard.insertText('Command');
  await page.mouse.move(more.x,more.y);await page.waitForTimeout(100);await wait('Search forward:');
  await page.keyboard.insertText(' help');await seq('Enter');
  assert((await text()).includes('Command help fixture'));console.log('PASS mouse hover does not cancel incremental search');
  await page.keyboard.insertText('dirty');await seq('Control+x','Control+c');await wait('really exit');
  await page.mouse.move(save.x,save.y);await page.waitForTimeout(100);await wait('really exit');await seq('n');
  assert(!page.isClosed());assert.equal(saves,0);assert.deepEqual(errors,[]);
  console.log('PASS hover cannot answer an exit confirmation or execute Save');
 }finally{await browser.close();server.close();}
})().catch(e=>{console.error(e);server.close();process.exitCode=1;});
