// Development only (playwright, Chrome): M-x term in the browser editor.
// A web page cannot start a shell, so M-x term says so, and leaves no
// *terminal* buffer behind: the buffer it was in stays, with its text.
const {chromium}=require('playwright');
const http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');
const server=http.createServer((q,r)=>{
 if(q.url==='/session'){r.end('Untouched text\n');return;}
 if(q.url==='/name'){r.end('notes.txt');return;}
 let file=q.url==='/'?'Chezweb.html':q.url.slice(1);
 if(!['Chezweb.html','build/chezweb.js','build/chezweb.wasm'].includes(file)){r.writeHead(404);r.end();return;}
 r.setHeader('Content-Type',file.endsWith('.wasm')?'application/wasm':file.endsWith('.js')?'text/javascript':'text/html');r.end(fs.readFileSync(path.join(root,file)));
});
(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await chromium.launch({channel:'chrome'});
 try{
  const page=await browser.newPage({viewport:{width:1000,height:600}}),errors=[];page.on('pageerror',e=>errors.push(e.stack));
  const text=()=>page.locator('#screen-text').textContent();
  const wait=async s=>{try{await page.waitForFunction(s=>document.getElementById('screen-text').textContent.includes(s),s,{timeout:20000});}catch(e){console.error(await text());throw e;}};
  await page.goto('http://127.0.0.1:'+server.address().port);await wait('Untouched text');
  await page.keyboard.press('Alt+x');await page.keyboard.insertText('term');await page.keyboard.press('Enter');
  await wait('a browser page cannot start a shell');
  const t=await text();
  assert(t.includes('Untouched text')&&!t.includes('*terminal*'),t);
  await page.keyboard.press('Control+x');await page.keyboard.press('b');await page.keyboard.insertText('*term');await page.keyboard.press('Tab');
  await page.waitForTimeout(300);assert(!(await text()).includes('*terminal*'),'a *terminal* buffer was left behind');
  await page.keyboard.press('Control+g');
  assert.deepStrictEqual(errors,[]);
  console.log('PASS M-x term in the browser says why not, and leaves no buffer behind');
 }finally{await browser.close();server.close();}
})().catch(e=>{console.error(e);process.exit(1);});
