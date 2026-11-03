// Development only (playwright, Chrome): your ~/.chezemax files reach the
// browser editor through the real chezweb-server, read-only, and C-x C-r
// fetches them again.  A disposable home folder; nothing of yours is read.
const {chromium}=require('playwright');
const fs=require('fs'),os=require('os'),path=require('path'),assert=require('assert'),{spawn}=require('child_process');
const root=path.resolve(__dirname,'..');
const home=fs.mkdtempSync(path.join(os.tmpdir(),'chezweb-home-')),session=fs.mkdtempSync(path.join(os.tmpdir(),'chezweb-session-'));
const config=path.join(home,'.chezemax');
fs.mkdirSync(path.join(config,'extensions'),{recursive:true});fs.mkdirSync(path.join(config,'languages'),{recursive:true});
fs.writeFileSync(path.join(config,'init.scm'),'(set! *fill-column* 66)\n(global-set-key "C-c 8" \'upcase-word)\n');
fs.writeFileSync(path.join(config,'extensions','greet.scm'),'(global-set-key "C-c 9" \'capitalize-word)\n');
fs.writeFileSync(path.join(config,'extensions','.hidden.scm'),'(error "a hidden file was loaded")\n');
fs.writeFileSync(path.join(config,'secret.txt'),'never served\n');
fs.writeFileSync(path.join(session,'initial'),'settings test\n');fs.writeFileSync(path.join(session,'name'),'notes.txt');
const token='ab'.repeat(24),server=spawn(path.join(root,'chezweb-server'),[root,session,token],{env:{...process.env,HOME:home},stdio:'inherit'});
(async()=>{
 let url='';for(let i=0;i<100&&!url;i++){try{url=fs.readFileSync(path.join(session,'ready'),'utf8').trim();}catch(_){await new Promise(r=>setTimeout(r,50));}}
 const browser=await chromium.launch({channel:'chrome',headless:true});
 try{
  const bundle=await (await fetch(url+'settings')).text();
  assert(bundle.startsWith('CHEZWEB-SETTINGS 1\n')&&bundle.includes('init.scm\n')&&bundle.includes('extensions/greet.scm\n'));
  assert(!bundle.includes('hidden')&&!bundle.includes('never served'));
  console.log('PASS the server gives only languages/, extensions/ and init.scm');
  const page=await browser.newPage({viewport:{width:1100,height:740}}),errors=[];page.on('pageerror',e=>errors.push(e.stack));
  const text=()=>page.locator('#screen-text').textContent();
  const wait=async s=>{try{await page.waitForFunction(s=>document.getElementById('screen-text').textContent.includes(s),s,{timeout:20000});}catch(e){console.error('SCREEN:',await text(),'ERRORS:',errors);throw e;}};
  const seq=async(...keys)=>{for(const key of keys)await page.keyboard.press(key);};
  const evaluate=async(expr,expected)=>{await seq('Escape','Shift+Semicolon');await wait('Eval');await page.keyboard.insertText(expr);await seq('Enter');await wait(expected);};
  await page.goto(url);await wait('settings test');
  await evaluate('*fill-column*','66');console.log('PASS init.scm set *fill-column*');
  await seq('Escape','Shift+Period');await page.keyboard.insertText(' lower');await seq('Alt+b','Control+c','8');await wait('LOWER');console.log('PASS init.scm bound C-c 8');
  await page.keyboard.insertText(' second');await seq('Alt+b','Control+c','9');await wait('Second');console.log('PASS an extension bound C-c 9');
  await evaluate('(no-such-procedure 1)','unbound variable no-such-procedure');console.log('PASS an error says what went wrong, as in the terminal');
  fs.writeFileSync(path.join(config,'init.scm'),'(set! *fill-column* 55)\n');
  await seq('Control+x','Control+r');await wait('Your files reloaded');await evaluate('*fill-column*','55');console.log('PASS C-x C-r fetches your files again');
  assert.deepStrictEqual(errors,[]);
  console.log('PASS your ~/.chezemax files in the browser editor');
 }finally{await browser.close();server.kill();fs.rmSync(home,{recursive:true,force:true});fs.rmSync(session,{recursive:true,force:true});}
})().catch(e=>{console.error(e);process.exit(1);});
