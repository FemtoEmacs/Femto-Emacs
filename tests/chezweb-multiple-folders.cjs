// Real Chrome and explicit, independent mock directory grants. No user files.
const {chromium}=require('playwright');
const http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..'),requests=[];
const server=http.createServer((q,r)=>{requests.push(q.url);if(q.url==='/session'){r.end('Multiple folder test\n');return;}if(q.url==='/name'){r.end('source.md');return;}const name=q.url==='/'?'Chezweb.html':q.url.slice(1);if(!['Chezweb.html','build/chezweb.js','build/chezweb.wasm'].includes(name)){r.writeHead(404);r.end();return;}r.setHeader('Content-Type',name.endsWith('.wasm')?'application/wasm':name.endsWith('.js')?'text/javascript':'text/html');r.end(fs.readFileSync(path.join(root,name)));});
(async()=>{await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await chromium.launch({channel:'chrome',headless:true});try{
 const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.addInitScript(()=>{
  window.access={pickers:0,writes:0,creates:0,reads:0,lists:[],next:[]};
  function file(name,text){return {kind:'file',name,getFile:async()=>{var f=new File([text],name),read=f.arrayBuffer.bind(f);f.arrayBuffer=async()=>{access.reads++;return await read();};return f;},createWritable:async()=>{access.writes++;throw Error('Unexpected write');}};}
  function dir(name,id,entries){return {kind:'directory',name,id,isSameEntry:async other=>other.id===id,async *values(){access.lists.push(id);yield* entries;},getDirectoryHandle:async()=>{access.creates++;throw Error('Unexpected creation');},getFileHandle:async()=>{access.creates++;throw Error('Unexpected creation');}};}
  window.roots={codex:dir('codex-sand','first',[file('codex.txt','First folder\n')]),claude:dir('claude-sandbox','second',[dir('chezweb','nested',[file('editor.scm','(display "third directory")\n')])]),external:dir('research','outside',[file('paper.txt','External volume\n')]),other:dir('codex-sand','same-name',[file('other.txt','Different folder with same name\n')]),picked:dir('picked','picked',[file('picked.txt','Arbitrary selection\n')])};
  window.showDirectoryPicker=async()=>{access.pickers++;var name=access.next.shift();if(name==='cancel')throw new DOMException('Cancelled','AbortError');if(!roots[name])throw Error('Unexpected picker: '+name);return roots[name];};
 });
 const wait=async s=>{try{await page.waitForFunction(s=>document.getElementById('screen-text').textContent.includes(s),s,{timeout:15000});}catch(e){console.error(await page.locator('#screen-text').textContent(),errors);throw e;}};
 const seq=async(...keys)=>{for(const k of keys)await page.keyboard.press(k);};
 const type=s=>page.keyboard.insertText(s);
 const pick=name=>page.evaluate(name=>access.next.push(name),name);
 const mini=async command=>{await seq('Control+c','m');await wait('Command:');await type(command);await seq('Enter');await wait('$ '+command);};
 await page.goto('http://127.0.0.1:'+server.address().port);await wait('Multiple folder test');
 await pick('codex');await mini('cd ~/codex-sand');await wait('~/codex-sand');await mini('ls');await wait('codex.txt');
 await pick('claude');await mini('cd ../claude-sandbox');await wait('~/claude-sandbox');await mini('ls');await wait('chezweb/');
 await mini('ls ~/codex-sand');await wait('codex.txt');assert.equal(await page.evaluate(()=>access.pickers),2);assert.equal(await page.evaluate(()=>access.reads),0);console.log('PASS cd leaves the first grant, requests a second directory, and retains both grants without file-content reads');
 await pick('external');await mini('ls /Volumes/Archive/research');await wait('paper.txt');assert.equal(await page.evaluate(()=>access.pickers),3);
 await mini('cd /Volumes/Archive/research');await mini('pwd');await wait('/Volumes/Archive/research');console.log('PASS ls requests its missing target directly, including absolute paths outside browser HOME');
 await pick('picked');await seq('Control+c','m');await wait('Command:');await type('cd --p');await seq('Tab');await wait('Command: cd --pick');await seq('Enter');await wait('~/picked');
 await seq('Control+x','Control+f');await wait('Find file: ~/picked/');await seq('Control+g');console.log('PASS cd --pick selects any directory and updates the editable file prompt');
 await pick('other');await page.getByRole('button',{name:'Choose folder',exact:true}).click();await page.waitForFunction(()=>Module.FS.cwd()==='/home/web_user/codex-sand-2');
 await mini('ls');await wait('other.txt');await mini('ls ~/codex-sand');await wait('codex.txt');assert.equal(await page.evaluate(()=>access.pickers),5);console.log('PASS Choose folder grants another location; identical directory names receive separate paths instead of replacing a grant');
 await pick('cancel');await mini('cd --pick');await wait('exit status 1');await mini('pwd');await wait('~/codex-sand-2');
 await pick('cancel');await page.getByRole('button',{name:'Choose folder',exact:true}).click();await page.waitForFunction(()=>document.getElementById('notice').textContent==='Folder selection cancelled.');assert.equal(await page.evaluate(()=>Module.FS.cwd()),'/home/web_user/codex-sand-2');console.log('PASS cancelled picker preserves the directory and all existing grants');
 await pick('external');await mini('ls --pick');await wait('paper.txt');await mini('pwd');await wait('~/codex-sand-2');console.log('PASS ls --pick lists an independently selected folder without changing the working directory');
 await mini('cd ~/claude-sandbox/chezweb');await seq('Control+x','Control+f');await wait('Find file: ~/claude-sandbox/chezweb/');await type('ed');await seq('Tab');await wait('editor.scm');await seq('Enter');await wait('third directory');
 assert.equal(await page.evaluate(()=>access.writes),0);assert.equal(await page.evaluate(()=>access.creates),0);assert.deepEqual(errors,[]);assert(!requests.some(x=>/shell|files|codex|claude/.test(x)));console.log('PASS nested file completion across retained grants; no file writes, creates or native-shell endpoint');
 await page.screenshot({path:'/private/tmp/chezweb-multiple-folders.png'});
 }finally{await browser.close();server.close();}})().catch(e=>{console.error(e);server.close();process.exitCode=1;});
