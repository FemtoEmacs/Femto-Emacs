// Development only (playwright, Chrome): M-x latex-export in the browser
// editor, on a Markdown file of a granted folder (a pretend one that
// records every write).  paper.tex is created beside paper.md, through
// the folder's handle, and holds the LaTeX.
const {chromium}=require('playwright');
const http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');
const server=http.createServer((q,r)=>{if(q.url==='/session'){r.end('Untouched starting buffer\n');return;}if(q.url==='/name'){r.end('start.md');return;}let name=q.url==='/'?'Chezweb.html':q.url.slice(1);if(!['Chezweb.html','build/chezweb.js','build/chezweb.wasm'].includes(name)){r.writeHead(404);r.end();return;}r.setHeader('Content-Type',name.endsWith('.wasm')?'application/wasm':name.endsWith('.js')?'text/javascript':'text/html');r.end(fs.readFileSync(path.join(root,name)));});
(async()=>{await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await chromium.launch({channel:'chrome',headless:true});try{
 const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.addInitScript(()=>{
  window.access={writes:[],creates:[]};
  function file(name,text){return {kind:'file',name,getFile:async()=>new File([text],name,{lastModified:123}),createWritable:async()=>({write:async b=>access.writes.push([name,new TextDecoder().decode(b)]),close:async()=>{}})};}
  var entries=[file('paper.md','# A paper\n\nSome **bold** text and $x^2$.\n\n- one\n- two\n')];
  var folder={kind:'directory',name:'documents',async *values(){yield* entries;},getDirectoryHandle:async()=>undefined,getFileHandle:async(n,o)=>{if(o&&o.create)access.creates.push(n);var e=entries.find(x=>x.name===n);if(e)return e;var added=file(n,'');entries.push(added);return added;}};
  window.showDirectoryPicker=async()=>folder;
 });
 const wait=async s=>{try{await page.waitForFunction(s=>document.getElementById('screen-text').textContent.includes(s),s,{timeout:15000});}catch(e){console.error(await page.locator('#screen-text').textContent(),errors);throw e;}};
 const seq=async(...keys)=>{for(const k of keys)await page.keyboard.press(k);};
 await page.goto('http://127.0.0.1:'+server.address().port);await wait('Untouched starting buffer');
 await seq('Control+x','Control+f');await wait('Find');await seq('Control+a','Control+k');await page.keyboard.insertText('~/doc');await seq('Tab');await wait('~/documents/');
 await page.keyboard.insertText('paper.md');await seq('Enter');await wait('Some **bold** text');
 await seq('Alt+x');await page.keyboard.insertText('latex-export');await seq('Enter');
 await page.waitForFunction(()=>access.writes.some(w=>w[0]==='paper.tex'));await wait('Wrote paper.tex');
 const tex=await page.evaluate(()=>access.writes.find(w=>w[0]==='paper.tex')[1]);
 assert(tex.includes('\\title{A paper}')&&tex.includes('Some \\textbf{bold} text and $x^2$.')&&tex.includes('\\item one'),tex);
 assert.deepEqual(await page.evaluate(()=>access.creates),['paper.tex']);
 assert(!(await page.evaluate(()=>access.writes.some(w=>w[0]==='paper.md'))),'paper.md was written');
 assert.deepEqual(errors,[]);
 console.log('PASS M-x latex-export in the browser writes paper.tex beside paper.md, in the granted folder');
 }finally{await browser.close();server.close();}})().catch(e=>{console.error(e);server.close();process.exitCode=1;});
