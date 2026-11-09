// Development only (playwright, Chrome).  The logbook's 9 November 2026
// complaint: at "Find file: ~/mysand/chezmoi/or", TAB asked for a folder,
// the user chose chezmoi, and every later TAB asked again, because only a
// folder named mysand (the path's first component) was accepted.  Any
// folder the typed path names must do, mapped where the path puts it.
// Mock folders only: nothing on the computer is read or written.
const {chromium}=require('playwright');
const http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');
const server=http.createServer((q,r)=>{if(q.url==='/session'){r.end('Tab grant test\n');return;}if(q.url==='/name'){r.end('start.md');return;}const name=q.url==='/'?'Chezweb.html':q.url.slice(1);if(!['Chezweb.html','build/chezweb.js','build/chezweb.wasm'].includes(name)){r.writeHead(404);r.end();return;}r.setHeader('Content-Type',name.endsWith('.wasm')?'application/wasm':name.endsWith('.js')?'text/javascript':'text/html');r.end(fs.readFileSync(path.join(root,name)));});
(async()=>{await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await chromium.launch({channel:'chrome',headless:true});try{
 const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.addInitScript(()=>{
  window.access={pickers:0,writes:0,next:[]};
  function file(name,text){return {kind:'file',name,getFile:async()=>new File([text],name),createWritable:async()=>{access.writes++;throw Error('Unexpected write');}};}
  function dir(name,entries){return {kind:'directory',name,async *values(){yield* entries;},getDirectoryHandle:async()=>{throw Error('Unexpected creation');},getFileHandle:async()=>{throw Error('Unexpected creation');}};}
  window.roots={
   chezmoi:dir('chezmoi',[dir('orgmode',[file('notes.org','* Org notes in chezmoi\n')]),file('README.md','readme\n')]),
   stray:dir('stray',[file('stray.txt','not this one\n')]),
   work:dir('work',[dir('site',[file('index.html','<p>site</p>\n')])])};
  window.showDirectoryPicker=async()=>{access.pickers++;var name=access.next.shift();if(!roots[name])throw Error('Unexpected picker: '+name);return roots[name];};
 });
 const wait=async s=>{try{await page.waitForFunction(s=>document.getElementById('screen-text').textContent.includes(s),s,{timeout:15000});}catch(e){console.error(await page.locator('#screen-text').textContent(),errors);throw e;}};
 const notice=async s=>{try{await page.waitForFunction(s=>document.getElementById('notice').textContent.includes(s),s,{timeout:15000});}catch(e){console.error(await page.locator('#notice').textContent(),errors);throw e;}};
 const seq=async(...keys)=>{for(const k of keys)await page.keyboard.press(k);};
 const type=s=>page.keyboard.insertText(s);
 const pick=name=>page.evaluate(name=>access.next.push(name),name);
 const pickers=()=>page.evaluate(()=>access.pickers);
 const openPrompt=async value=>{await seq('Control+x','Control+f');await wait('Find');await seq('Control+a','Control+k');if(value)await type(value);};
 await page.goto('http://127.0.0.1:'+server.address().port);await wait('Tab grant test');

 // The wrong folder is refused, says which ones will do, and grants nothing.
 await pick('stray');await openPrompt('~/mysand/chezmoi/or');await seq('Tab');
 await notice('needs the chezmoi or mysand folder, not stray');assert.equal(await pickers(),1);
 await seq('Control+g');console.log('PASS a folder the path does not name is refused, naming chezmoi and mysand');

 // chezmoi, the path's second folder, is accepted at ~/mysand/chezmoi.
 await pick('chezmoi');await openPrompt('~/mysand/chezmoi/or');await seq('Tab');
 await wait('~/mysand/chezmoi/orgmode/');assert.equal(await pickers(),2);
 await notice('~/mysand/chezmoi/');
 await type('no');await seq('Tab');await wait('~/mysand/chezmoi/orgmode/notes.org');assert.equal(await pickers(),2);
 await seq('Enter');await wait('Org notes in chezmoi');
 console.log('PASS choosing chezmoi grants ~/mysand/chezmoi; the next TABs complete folder and file without asking again');

 await openPrompt('~/mysand/chezmoi/RE');await seq('Tab');await wait('~/mysand/chezmoi/README.md');assert.equal(await pickers(),2);
 await seq('Control+g');console.log('PASS a new C-x C-f in the granted folder completes without a picker');

 // The shell's cd: a folder above the target also does.
 await pick('work');await seq('Control+c','m');await wait('Command:');await type('cd ~/work/site');await seq('Enter');await wait('$ cd ~/work/site');
 await seq('Control+c','m');await wait('Command:');await type('ls');await seq('Enter');await wait('index.html');assert.equal(await pickers(),3);
 console.log('PASS cd ~/work/site accepts the work folder and enters site');

 assert.equal(await page.evaluate(()=>access.writes),0);assert.deepEqual(errors,[]);
}finally{await browser.close();server.close();}})().catch(e=>{console.error(e);process.exit(1);});
