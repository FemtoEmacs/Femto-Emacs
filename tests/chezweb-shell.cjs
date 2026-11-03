// Real Chrome UI and disposable directory handles; never a real shell/API.
const {chromium}=require('playwright');
const http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..'),requests=[];
const server=http.createServer((q,r)=>{requests.push(q.url);if(q.url==='/session'){r.end('Shell test source\n');return;}if(q.url==='/name'){r.end('source.md');return;}let n=q.url==='/'?'Chezweb.html':q.url.slice(1);if(!['Chezweb.html','build/chezweb.js','build/chezweb.wasm'].includes(n)){r.writeHead(404);r.end();return;}r.setHeader('Content-Type',n.endsWith('.wasm')?'application/wasm':n.endsWith('.js')?'text/javascript':'text/html');r.end(fs.readFileSync(path.join(root,n)));});
(async()=>{await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await chromium.launch({channel:'chrome',headless:true});try{
 const page=await browser.newPage({viewport:{width:1100,height:740}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.addInitScript(()=>{
  window.effects={reads:0,writes:0,creates:0};
  function file(name,text){return {kind:'file',name,getFile:async()=>{var f=new File([text],name),read=f.arrayBuffer.bind(f);f.arrayBuffer=async()=>{effects.reads++;return await read();};return f;},createWritable:async()=>{effects.writes++;throw Error('No write expected');}};}
  function dir(name,entries){return {kind:'directory',name,async *values(){yield* entries;},getDirectoryHandle:async()=>{effects.creates++;throw Error('No directory creation expected');},getFileHandle:async()=>{effects.creates++;throw Error('No file creation expected');}};}
  window.showDirectoryPicker=async()=>dir('workspace',[file('alpha.txt','Alpha real bytes\n'),file('space name.txt','Spaces\n'),file('.hidden','Hidden\n'),dir('nested',[file('inside.txt','Nested bytes\n')])]);
 });
 const screen=()=>page.locator('#screen-text').textContent();
 const wait=async s=>{try{await page.waitForFunction(s=>document.getElementById('screen-text').textContent.includes(s),s,{timeout:15000});}catch(e){console.error(await screen(),errors);throw e;}};
 const seq=async(...keys)=>{for(const k of keys)await page.keyboard.press(k);};
 const type=s=>page.keyboard.insertText(s);
 const mini=async command=>{await seq('Control+c','m');await wait('Command:');await type(command);await seq('Enter');await wait('$ '+command);};
 await page.goto('http://127.0.0.1:'+server.address().port);await wait('Shell test source');
 await seq('Control+x','Control+f');await wait('Find');await seq('Control+a','Control+k');await type('~/work');await seq('Tab');await wait('~/workspace/');await seq('Control+g');
 var boxes=await page.evaluate(()=>({notice:document.getElementById('notice').getBoundingClientRect().bottom,canvas:document.getElementById('screen').getBoundingClientRect().top}));assert(boxes.notice<=boxes.canvas,'notices must never overlap the editing canvas');await page.waitForFunction(()=>document.getElementById('notice').hidden,null,{timeout:6500});console.log('PASS reserved notice row stays outside buffer; ordinary notices expire');
 await page.dispatchEvent('#keys','keydown',{key:'¡',code:'Digit1',altKey:true,shiftKey:true});await wait('*shell-command*');await type('ls ~/workspace');await seq('Control+c','s');await wait('alpha.txt');assert((await screen()).includes('nested/'));assert.equal(await page.evaluate(()=>effects.reads),0);console.log('PASS M-! command buffer executes ls without reading file contents or writing');
 await seq('Control+c','m');await wait('Command:');await type('p');await seq('Tab');await wait('Command: pwd');await seq('Enter');await wait('$ pwd');console.log('PASS C-c m executes pwd with command-name Tab completion');
 await seq('Control+c','m');await wait('Command:');await type('cd ~/work');await seq('Tab');await wait('cd ~/workspace/');await seq('Enter');await wait('~/workspace');
 await seq('Control+x','Control+f');await wait('Find file: ~/workspace/');await type('al');await seq('Tab');await wait('alpha.txt');await seq('Enter');await wait('Alpha real bytes');console.log('PASS cd path completion updates C-x C-f starting directory');
 await mini('cd nested && pwd');await wait('~/workspace/nested');await mini('ls');await wait('inside.txt');
 await seq('Control+x','Control+f');await wait('Find file: ~/workspace/nested/');await seq('Control+g');await mini('cd -');await wait('~/workspace');await mini('ls "space name.txt"');await wait('space name.txt');console.log('PASS shared cwd, relative navigation, cd -, quotes and read-only listings');
 await seq('Escape','Shift+Digit1');await wait('*shell-command*');await type('cd ne');await seq('Tab');await wait('cd nested/');await seq('Control+c','s');await wait('~/workspace/nested');
 await seq('Control+c','m');await wait('Command:');await type('cd ..');await seq('Control+g');await mini('pwd');assert((await screen()).includes('~/workspace/nested'));console.log('PASS M-! path completion and minibuffer cancellation preserve the command directory');
 for(const command of ['rm inside.txt','curl https://example.com','echo unsafe','ls > created.txt','ls | pwd','pwd $(touch unwanted)']){await mini(command);await wait(command.includes('>')||command.includes('|')||command.includes('$')?'exit status 2':'exit status 127');}
 assert.equal(await page.evaluate(()=>effects.writes),0);assert.equal(await page.evaluate(()=>effects.creates),0);assert(!requests.some(p=>/shell|codex|claude/.test(p)));assert.deepEqual(errors,[]);console.log('PASS non-whitelisted commands, pipes, redirects and expansion rejected; no writes, processes or shell endpoint');
 await mini('ls -al .. && pwd');await wait('.hidden');await wait('~/workspace/nested');await page.screenshot({path:'/private/tmp/chezweb-shell-tested.png'});
 }finally{await browser.close();server.close();}})().catch(e=>{console.error(e);server.close();process.exitCode=1;});
