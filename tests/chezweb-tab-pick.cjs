// Development only (playwright, Chrome): in C-c m, TAB at ~/ before any
// folder is granted asks for one, as C-x C-f does.  The picker is a stub
// that is cancelled: nothing is granted, read or written.
const {chromium}=require('playwright');const http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');
const server=http.createServer((q,r)=>{let f=q.url==='/'?'Chezweb.html':q.url.slice(1);if(!['Chezweb.html','build/chezweb.js','build/chezweb.wasm'].includes(f)){r.writeHead(404);r.end();return;}
 r.setHeader('Content-Type',f.endsWith('.wasm')?'application/wasm':f.endsWith('.js')?'text/javascript':'text/html');r.end(fs.readFileSync(path.join(root,f)));});
(async()=>{await new Promise(r=>server.listen(0,'127.0.0.1',r));const b=await chromium.launch({channel:'chrome'});
 try{const p=await b.newPage();
  await p.addInitScript(()=>{window.picks=0;window.showDirectoryPicker=async()=>{window.picks++;throw new DOMException('cancel','AbortError');};});
  await p.goto('http://127.0.0.1:'+server.address().port);await p.waitForFunction(()=>document.getElementById('starting').hidden,null,{timeout:20000});
  for(const typed of ['cd ','ls ~/']){
   const before=await p.evaluate(()=>window.picks);
   await p.keyboard.press('Control+c');await p.keyboard.press('m');await p.waitForTimeout(300);await p.keyboard.insertText(typed);await p.keyboard.press('Tab');
   await p.waitForFunction(n=>window.picks>n,before,{timeout:5000});await p.keyboard.press('Control+g');
   console.log('PASS C-c m: "'+typed+'" TAB asks for a folder');}
 }finally{await b.close();server.close();}
})().catch(e=>{console.error(e);process.exit(1);});
