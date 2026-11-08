// Development only (playwright, Chrome): M-x polytonic in the browser
// editor, the same compiled script as in the terminal.  Beta Code typed
// with the keyboard gives precomposed polytonic Greek on the screen.
const {chromium}=require('playwright');
const http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');
const server=http.createServer((q,r)=>{
 if(q.url==='/session'){r.end('\n');return;}
 if(q.url==='/name'){r.end('greek.txt');return;}
 let file=q.url==='/'?'Chezweb.html':q.url.slice(1);
 if(!['Chezweb.html','build/chezweb.js','build/chezweb.wasm'].includes(file)){r.writeHead(404);r.end();return;}
 r.setHeader('Content-Type',file.endsWith('.wasm')?'application/wasm':file.endsWith('.js')?'text/javascript':'text/html');r.end(fs.readFileSync(path.join(root,file)));
});
(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await chromium.launch({channel:'chrome'});
 try{
  const page=await browser.newPage({viewport:{width:1000,height:600}}),errors=[];page.on('pageerror',e=>errors.push(e.stack));
  const wait=async s=>{try{await page.waitForFunction(s=>document.getElementById('screen-text').textContent.includes(s),s,{timeout:20000});}catch(e){console.error(await page.locator('#screen-text').textContent());throw e;}};
  await page.goto('http://127.0.0.1:'+server.address().port);await wait('[SAVE]');
  await page.keyboard.press('Alt+x');await page.keyboard.insertText('polytonic');await page.keyboard.press('Enter');await wait('Ἑλ');
  for(const ch of '*)en a)rxh=| h)=n o( lo/gos, ')await page.keyboard.type(ch);
  await wait('Ἐν ἀρχῇ ἦν ὁ λόγος, ');
  assert.deepStrictEqual(errors,[]);
  console.log('PASS Beta Code types polytonic Greek in the browser editor');
 }finally{await browser.close();server.close();}
})().catch(e=>{console.error(e);process.exit(1);});
