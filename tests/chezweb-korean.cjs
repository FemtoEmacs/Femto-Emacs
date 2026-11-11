// Development only (playwright, Chrome): M-x korean-input in the browser
// editor, the same compiled script as in the terminal.  The 2-set keys
// typed with the keyboard give Hangul syllables on the screen, DEL taking
// back one jamo.
const {chromium}=require('playwright');
const http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');
const server=http.createServer((q,r)=>{
 if(q.url==='/session'){r.end('\n');return;}
 if(q.url==='/name'){r.end('korean.txt');return;}
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
  await page.keyboard.press('Alt+x');await page.keyboard.insertText('korean-input');await page.keyboard.press('Enter');await wait(' 한 ');
  for(const ch of 'gksrmf dkssudgktpdy ekfrk rkf')await page.keyboard.type(ch);
  await page.keyboard.press('Backspace');await page.keyboard.type('r');
  await wait('한글 안녕하세요 달가 각');
  assert.deepStrictEqual(errors,[]);
  console.log('PASS the 2-set keyboard types Hangul in the browser editor');
  // The spaces must show, and only they: on a new line, 이상순 한글 is drawn;
  // the blank columns between the syllables of a word are narrower than
  // half a cell, the one between the words at least a cell
  await page.keyboard.press('Enter');for(const ch of 'dltkdtns gksrmf')await page.keyboard.type(ch);await wait('이상순 한글');
  const gaps=await page.evaluate(()=>{
   const g=Module.browsered.layerGeometry(),c=document.getElementById('screen'),d=devicePixelRatio||1,x=c.getContext('2d');
   const y0=Math.round((g.pad+g.ch)*d),h=Math.round(g.ch*d),w=Math.round((g.pad+11*g.cw)*d);
   const img=x.getImageData(0,y0,w,h).data,bg=[img[0],img[1],img[2]],ink=[];
   for(let i=0;i<w;i++){let on=false;for(let j=0;j<h&&!on;j++){const k=(j*w+i)*4;on=Math.abs(img[k]-bg[0])+Math.abs(img[k+1]-bg[1])+Math.abs(img[k+2]-bg[2])>120;}ink.push(on);}
   const runs=[];let start=-1;for(let i=0;i<=w;i++){if(i<w&&!ink[i]){if(start<0)start=i;}else if(start>=0){runs.push([start,i-start]);start=-1;}}
   const first=ink.indexOf(true);return {cw:g.cw*d,gaps:runs.filter(r=>r[0]>first&&r[0]+r[1]<w).map(r=>r[1])};
  });
  const wide=gaps.gaps.filter(n=>n>=gaps.cw),narrow=gaps.gaps.filter(n=>n<gaps.cw);
  assert.equal(wide.length,1,'one blank as wide as a cell (the space): '+JSON.stringify(gaps));
  assert(narrow.every(n=>n<gaps.cw/2),'the syllables of a word leave no visible gap: '+JSON.stringify(gaps));
  console.log('PASS wide characters fill their two cells: 이상순 한글 shows one space, not five');
 }finally{await browser.close();server.close();}
})().catch(e=>{console.error(e);process.exit(1);});
