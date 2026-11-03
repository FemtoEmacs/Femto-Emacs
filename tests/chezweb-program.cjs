// Development only (playwright, Chrome): your compiled scripts
// (~/.chezemax/chezemax.wasm, from chezweb --compile-scripts) run in the
// browser editor as in the terminal: used when not older than Chezweb's
// own and they start; otherwise Chezweb's own, and the editor says why.
// CHEZWEB_TEST_PROGRAM names a compiled program whose users/ code defines
// (mean xs); tests/run-chezweb-program.sh makes one.  A disposable home.
const {chromium}=require('playwright');
const fs=require('fs'),os=require('os'),path=require('path'),assert=require('assert'),{spawn}=require('child_process');
const root=path.resolve(__dirname,'..'),compiled=process.env.CHEZWEB_TEST_PROGRAM;
assert(compiled&&fs.existsSync(compiled),'set CHEZWEB_TEST_PROGRAM to a compiled program defining mean');
async function run(prepare,check){
 const home=fs.mkdtempSync(path.join(os.tmpdir(),'chezweb-home-')),session=fs.mkdtempSync(path.join(os.tmpdir(),'chezweb-session-'));
 fs.mkdirSync(path.join(home,'.chezemax'));prepare(path.join(home,'.chezemax','chezemax.wasm'));
 fs.writeFileSync(path.join(session,'initial'),'program test\n');fs.writeFileSync(path.join(session,'name'),'notes.txt');
 const server=spawn(path.join(root,'chezweb-server'),[root,session,'ef'.repeat(24)],{env:{...process.env,HOME:home},stdio:'inherit'});
 const browser=await chromium.launch({channel:'chrome'});
 try{let url='';for(let i=0;i<100&&!url;i++){try{url=fs.readFileSync(path.join(session,'ready'),'utf8').trim();}catch(_){await new Promise(r=>setTimeout(r,50));}}
  const page=await browser.newPage({viewport:{width:1100,height:740}}),errors=[];page.on('pageerror',e=>errors.push(e.stack));
  const wait=async s=>{try{await page.waitForFunction(s=>document.getElementById('screen-text').textContent.includes(s),s,{timeout:30000});}catch(e){console.error('SCREEN:',await page.locator('#screen-text').textContent(),errors);throw e;}};
  const evaluate=async(expr,expected)=>{await page.keyboard.press('Escape');await page.keyboard.press('Shift+Semicolon');await wait('Eval');await page.keyboard.insertText(expr);await page.keyboard.press('Enter');await wait(expected);};
  await page.goto(url);await wait('program test');await check(evaluate);assert.deepStrictEqual(errors,[]);
 }finally{await browser.close();server.kill();fs.rmSync(home,{recursive:true,force:true});fs.rmSync(session,{recursive:true,force:true});}
}
(async()=>{
 await run(p=>fs.copyFileSync(compiled,p),async ev=>{await ev('(mean (list 1 2 3 6))','3');});
 console.log('PASS your compiled scripts, with your users/ code, run in the browser');
 await run(p=>{fs.copyFileSync(compiled,p);const old=new Date('2000-01-01');fs.utimesSync(p,old,old);},
  async ev=>{await ev('(list (top-level-bound? (quote mean)) (car *init-errors*))','are older than this Chezemax');});
 console.log('PASS older compiled scripts are not used, and the editor says why');
 await run(p=>fs.writeFileSync(p,'not a program'),async ev=>{await ev('(list (top-level-bound? (quote mean)) (car *init-errors*))','did not start');});
 console.log('PASS compiled scripts that do not start are replaced by Chezweb\'s own, and the editor says why');
})().catch(e=>{console.error(e);process.exit(1);});
