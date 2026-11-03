// Real Chrome; pretend granted folder records every read and write.
const {chromium}=require('playwright');
const http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');
const server=http.createServer((q,r)=>{if(q.url==='/session'){r.end('Untouched starting buffer\n');return;}if(q.url==='/name'){r.end('start.md');return;}let name=q.url==='/'?'Chezweb.html':q.url.slice(1);if(!['Chezweb.html','build/chezweb.js','build/chezweb.wasm'].includes(name)){r.writeHead(404);r.end();return;}r.setHeader('Content-Type',name.endsWith('.wasm')?'application/wasm':name.endsWith('.js')?'text/javascript':'text/html');r.end(fs.readFileSync(path.join(root,name)));});
(async()=>{await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await chromium.launch({channel:'chrome',headless:true});try{
 const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.addInitScript(()=>{
  window.access={pickers:0,reads:[],lists:[],writes:[],creates:[],cancel:false};
  function file(name,text){return {kind:'file',name,getFile:async()=>{var f=new File([text],name,{lastModified:123});var read=f.arrayBuffer.bind(f);f.arrayBuffer=async()=>{access.reads.push(name);return await read();};return f;},createWritable:async()=>({write:async b=>access.writes.push([name,new TextDecoder().decode(b)]),close:async()=>{}})};}
  function dir(name,entries){return {kind:'directory',name,async *values(){access.lists.push(name);yield* entries;},getDirectoryHandle:async(n,o)=>{if(o&&o.create)access.creates.push(n);return entries.find(e=>e.kind==='directory'&&e.name===n);},getFileHandle:async(n,o)=>{if(o&&o.create)access.creates.push(n);var existing=entries.find(e=>e.name===n);if(existing)return existing;var added=file(n,'');entries.push(added);return added;}};}
  var nested=dir('nested',[file('inside.txt','Nested real file\n')]);var folder=dir('documents',[file('alpha-one.txt','First real file\n'),file('alpha-two.txt','Second real file\n'),file('ação.txt','Portuguese text\n'),file('large.txt','L'.repeat(9*1024*1024)),nested]);
  window.showDirectoryPicker=async()=>{access.pickers++;if(access.cancel)throw new DOMException('Cancelled','AbortError');return folder;};
 });
 const wait=async s=>{try{await page.waitForFunction(s=>document.getElementById('screen-text').textContent.includes(s),s,{timeout:15000});}catch(e){console.error(await page.locator('#screen-text').textContent(),errors);throw e;}};
 const seq=async(...keys)=>{for(const k of keys)await page.keyboard.press(k);};
 const type=s=>page.keyboard.insertText(s);
 const prompt=()=>page.locator('#screen-text').textContent();
 const openPrompt=async value=>{await seq('Control+x','Control+f');await wait('Find');await seq('Control+a','Control+k');if(value)await type(value);};
 await page.goto('http://127.0.0.1:'+server.address().port);await wait('Untouched starting buffer');
 assert.equal(await page.evaluate(()=>access.pickers),0);
 await openPrompt('~/doc');await seq('Tab');await wait('~/documents/');assert.equal(await page.evaluate(()=>access.pickers),1);assert.deepEqual(await page.evaluate(()=>access.lists),['documents']);assert.deepEqual(await page.evaluate(()=>access.reads),[]);assert.deepEqual(await page.evaluate(()=>access.writes),[]);console.log('PASS Tab grants a Chrome folder; partial root completes to its real name; listing is lazy and writes nothing');
 await type('al');await seq('Tab');await wait('alpha-');await seq('Tab');await wait('alpha-one.txt');await seq('Enter');await wait('First real file');assert.deepEqual(await page.evaluate(()=>access.reads),['alpha-one.txt']);assert.equal(await page.evaluate(()=>access.pickers),1);console.log('PASS common-prefix and cycling completion opens real file bytes, without a second picker');
 await openPrompt('~/documents/ne');await seq('Tab');await wait('nested/');await type('in');await seq('Tab');await wait('inside.txt');await seq('Enter');await wait('Nested real file');assert.deepEqual(await page.evaluate(()=>access.lists),['documents','nested']);console.log('PASS subdirectories are listed on demand, with nested file completion');
 await openPrompt('~/documents/aç');await seq('Tab');await wait('ação.txt');await seq('Enter');await wait('Portuguese text');console.log('PASS Unicode filename completion and opening');
 await openPrompt('~/documents/alpha-two.txt');await seq('Enter');await wait('Second real file');console.log('PASS Enter opens a granted file even without first pressing Tab');
 await seq('Escape','Shift+Period');await type('Explicit edit');await seq('Control+x','Control+s');await page.waitForFunction(()=>access.writes.length===1);assert((await page.evaluate(()=>access.writes[0][1])).includes('Explicit edit'));
 await seq('Control+x','Control+w');await page.waitForTimeout(100);await seq('Control+a','Control+k');await type('~/doc');await seq('Tab');await wait('~/documents/');await type('new.txt');await seq('Enter');await page.waitForFunction(()=>access.writes.length===2);assert.deepEqual(await page.evaluate(()=>access.creates),['new.txt']);console.log('PASS only explicit Save/Save As writes; new files are created in the granted folder');
 await openPrompt('~/documents/alpha');await seq('Tab','Control+g');assert.deepEqual(await page.evaluate(()=>access.creates),['new.txt']);
 await page.evaluate(()=>{access.cancel=true;});await openPrompt('~/missing/');await seq('Tab','Control+g');assert.equal(await page.evaluate(()=>access.writes.length),2);console.log('PASS cancelling completion or the folder picker writes nothing');
 var large=await page.evaluate(()=>{var b=Module.FS.readFile('/home/web_user/documents/large.txt');return [b.length,b[0],b[b.length-1],access.writes.length];});assert.deepEqual(large,[9*1024*1024,76,76,2]);console.log('PASS a large listed file is read lazily without emptying or writing it');
 assert.deepEqual(errors,[]);await page.screenshot({path:'/private/tmp/chezweb-file-completion.png'});
 }finally{await browser.close();server.close();}})().catch(e=>{console.error(e);server.close();process.exitCode=1;});
