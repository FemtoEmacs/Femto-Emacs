// Development only (playwright, Chrome): what the browser editor leaves to
// the terminal and SDL windows.  No [TTFY] on the mode line, C-c f and
// C-c p unbound, the assistants' keys and M-x commands say where they are,
// and the help page says that M-! and C-c m run only ls, cd and pwd.
const {chromium}=require('playwright');const http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');
const server=http.createServer((q,r)=>{let f=q.url==='/'?'Chezweb.html':q.url.slice(1);if(!['Chezweb.html','build/chezweb.js','build/chezweb.wasm'].includes(f)){r.writeHead(404);r.end();return;}
 r.setHeader('Content-Type',f.endsWith('.wasm')?'application/wasm':f.endsWith('.js')?'text/javascript':'text/html');r.end(fs.readFileSync(path.join(root,f)));});
(async()=>{await new Promise(r=>server.listen(0,'127.0.0.1',r));const b=await chromium.launch({channel:'chrome'});
 try{const p=await b.newPage({viewport:{width:1100,height:740}}),errors=[];p.on('pageerror',e=>errors.push(e.stack));
  const text=()=>p.locator('#screen-text').textContent();
  const wait=async s=>{try{await p.waitForFunction(s=>document.getElementById('screen-text').textContent.includes(s),s,{timeout:15000});}catch(e){console.error('SCREEN:',await text());throw e;}};
  const seq=async(...keys)=>{for(const k of keys)await p.keyboard.press(k);};
  await p.goto('http://127.0.0.1:'+server.address().port);await p.waitForFunction(()=>document.getElementById('starting').hidden,null,{timeout:20000});await wait('[MORE]');
  assert(!(await text()).includes('[TTFY]'));console.log('PASS no [TTFY] on the mode line');
  await seq('Control+c','y');await wait('terminal or SDL window');await seq('Control+g');
  await seq('Alt+x');await p.keyboard.insertText('ttfy-menu');await seq('Enter');await wait('Not in the browser editor');console.log('PASS assistants and TTFY say where they are');
  await seq('Escape','Shift+Semicolon');await wait('Eval');await p.keyboard.insertText('(list (key-binding "C-c f") (key-binding "C-c p"))');await seq('Enter');await wait('(#f #f)');console.log('PASS C-c f and C-c p are unbound');
  await seq('Control+c','h');await wait('This is the browser editor');const page=await text();
  assert(!/textify a PDF|plot, or show/.test(page));assert(page.includes('only ls, cd and pwd'));console.log('PASS the help page says what the browser does');
  assert.deepStrictEqual(errors,[]);
 }finally{await b.close();server.close();}
})().catch(e=>{console.error(e);process.exit(1);});
