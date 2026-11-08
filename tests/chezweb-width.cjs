// Development only (playwright, Chrome): combining accents and wide
// characters in the browser editor.  Decomposed polytonic Greek and
// accented Latin keep one cell per letter; CJK takes two cells; the cursor
// lands where the characters are drawn (the backdoor's record, read from
// the page's own files).  No real document is used.
const {chromium}=require('playwright');
const http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');
const acc=s=>s.normalize('NFD');
const text=acc('ἐν ἀρχῇ')+'\n'+acc('ação')+'\n中文x\n';
const server=http.createServer((q,r)=>{
 if(q.url==='/session'){r.end(text);return;}
 if(q.url==='/name'){r.end('width.c');return;}
 let file=q.url==='/'?'Chezweb.html':q.url.slice(1);
 if(!['Chezweb.html','build/chezweb.js','build/chezweb.wasm'].includes(file)){r.writeHead(404);r.end();return;}
 r.setHeader('Content-Type',file.endsWith('.wasm')?'application/wasm':file.endsWith('.js')?'text/javascript':'text/html');r.end(fs.readFileSync(path.join(root,file)));
});
(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await chromium.launch({channel:'chrome'});
 try{
  const page=await browser.newPage({viewport:{width:1000,height:600}}),errors=[];page.on('pageerror',e=>errors.push(e.stack));
  const screen=()=>page.locator('#screen-text').textContent();
  await page.goto('http://127.0.0.1:'+server.address().port);
  await page.waitForFunction(()=>document.getElementById('screen-text').textContent.includes('中文x'),null,{timeout:20000});
  const lines=(await screen()).split('\n');
  // the screen's text: a letter and its accents in one cell, CJK in two
  assert(lines.some(l=>l.startsWith(acc('ἐν ἀρχῇ')+' ')),'Greek with combining accents, one cell a letter');
  assert(lines.some(l=>l.startsWith('中文x ')),'CJK drawn once, its second cells empty');
  const seq=async(...keys)=>{for(const k of keys)await page.keyboard.press(k);};
  await seq('Alt+x');await page.keyboard.insertText('backdoor-claude');await seq('Enter');
  await seq('Escape','Shift+Comma','Control+e','Control+n','Control+e','Control+n','Control+e','Control+p','Control+p');
  await page.waitForTimeout(500);
  await seq('Alt+x');await page.keyboard.insertText('backdoor-claude');await seq('Enter');
  await page.waitForTimeout(300);
  const log=await page.evaluate(()=>FS.readFile('/home/web_user/.chezemax/backdoor.txt',{encoding:'utf8'}));
  const cur=log.split('\n').filter(l=>/^#\d+ C-[enp] /.test(l)).map(l=>l.match(/cur=(\d+,\d+)/)[1]);
  // C-e: 7 letters of Greek; down: ação ends at 4; C-e there: 4; down at
  // column 4: x after 中文 (two cells each); C-e: 5; up: 4, then 4 again
  assert.deepStrictEqual(cur,['0,7','1,4','1,4','2,4','2,5','1,4','0,4'],'cursor columns '+cur.join(' '));
  assert(!/^(guard|reframe):/m.test(log),'no lost cursor');
  assert.deepStrictEqual(errors,[]);
  await page.screenshot({path:path.join(process.env.CHEZWEB_SHOT_DIR||'/tmp','chezweb-width.png')});
  console.log('PASS combining accents and wide characters: one cell a letter, two for CJK, the cursor where they are drawn');
 }finally{await browser.close();server.close();}
})().catch(e=>{console.error(e);process.exit(1);});
