// Screen/input adapter only. Editing policies and menus stay in Scheme/C.
Module.browsered=(function(){
 'use strict';
 var canvas,ctx,keys,queue=[],waiter=null,evals=[],rows=30,cols=100,last=null;
 var cw=9,ch=20,pad=4,points=15,ended=false,noticeTimer=null;
 function push(n){if(waiter){var w=waiter;waiter=null;w(n);}else queue.push(n);}
 function text(s){new TextEncoder().encode(s).forEach(push);}
 function layout(){var d=devicePixelRatio||1,top=canvas.getBoundingClientRect().top;canvas.width=innerWidth*d;canvas.height=(innerHeight-top)*d;canvas.style.width=innerWidth+'px';canvas.style.height=(innerHeight-top)+'px';ctx.setTransform(d,0,0,d,0,0);ctx.font=points+'px Menlo,Consolas,monospace';cw=ctx.measureText('MMMMMMMMMM').width/10;ch=Math.ceil(points*1.35);cols=Math.max(20,Math.floor((innerWidth-8)/cw));rows=Math.max(4,Math.floor((innerHeight-top-8)/ch));}
 function rgb(n){return '#'+(n&0xffffff).toString(16).padStart(6,'0');}
 function paint(p,nr,nc,r,c,bg,cursor){
  var grid=HEAP32.slice(p>>2,(p>>2)+nr*nc*4);last={grid,nr,nc,r,c};
  ctx.fillStyle=rgb(bg);ctx.fillRect(0,0,innerWidth,innerHeight);
  var lines=[];
  for(var y=0;y<nr;y++){var line='';for(var x=0;x<nc;x++){
   var i=(y*nc+x)*4,cp=grid[i]||32,fg=grid[i+1],back=grid[i+2],style=grid[i+3];
   ctx.fillStyle=rgb(y===r&&x===c?cursor:back);ctx.fillRect(pad+x*cw,pad+y*ch,cw,ch);
   ctx.fillStyle=rgb(y===r&&x===c?back:fg);ctx.font=(style&2?'italic ':'')+(style&1?'bold ':'')+points+'px Menlo,Consolas,monospace';ctx.fillText(String.fromCodePoint(cp),pad+x*cw,pad+y*ch+points);line+=String.fromCodePoint(cp);
  }lines.push(line);}document.getElementById('screen-text').textContent=lines.join('\n');
 }
  var shiftedPunct = { "`": "~", "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
    "6": "^", "7": "&", "8": "*", "9": "(", "0": ")", "-": "_", "=": "+", "[": "{",
    "]": "}", "\\": "|", ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?" };

  // the key's character on a US layout, from event.code (for Ctrl and Meta)
  function baseKey(e) {
    var code = e.code || "";
    if (/^Key[A-Z]$/.test(code)) return code.charAt(3).toLowerCase();
    if (/^Digit[0-9]$/.test(code)) return code.charAt(5);
    var map = { Space: " ", Minus: "-", Equal: "=", BracketLeft: "[", BracketRight: "]",
      Backslash: "\\", Semicolon: ";", Quote: "'", Comma: ",", Period: ".", Slash: "/",
      Backquote: "`" };
    if (code in map) return map[code];
    return e.key && e.key.length === 1 ? e.key.toLowerCase() : null;
  }


 function key(e){if(ended||e.isComposing||e.key==='Dead'||e.key==='Process')return;var s=null,k=baseKey(e),altGr=e.getModifierState&&e.getModifierState("AltGraph");
  if(e.metaKey&&!e.altKey&&!e.ctrlKey){if(e.key.toLowerCase()==='v')return;return;}
  if(e.ctrlKey&&!altGr&&k){var n=k.toUpperCase().charCodeAt(0);s=(e.altKey?'\x1b':'')+String.fromCharCode(k===' '||k==='2'?0:k==='/'||k==='-'?31:n>=64&&n<=95?n-64:n);}
  else if(e.altKey&&!altGr&&k){var ch=e.shiftKey?(shiftedPunct[k]||k.toUpperCase()):k;s='\x1b'+ch;}
  else s=({Enter:'\r',Escape:'\x1b',Backspace:'\x7f',Tab:'\t',ArrowUp:'\x1b[A',ArrowDown:'\x1b[B',ArrowRight:'\x1b[C',ArrowLeft:'\x1b[D',Home:'\x1bOH',End:'\x1bOF',Delete:'\x1b[3~',PageUp:'\x1b[5~',PageDown:'\x1b[6~'})[e.key];
  if(s!==undefined&&s!==null){e.preventDefault();e.stopImmediatePropagation();text(s);}
 }
 // Your ~/.chezemax files (languages, extensions, init.scm), read-only from
 // the native window's server: the compiled start-up loads them from the
 // browser's ~/.chezemax as the native editor does from yours.  Fetched again
 // by C-x C-r.  Without the server (a page opened by itself) there are none.
 async function settings(){
  var base='/home/web_user/.chezemax',bytes;
  try{var r=await fetch('settings',{cache:'no-store'});if(!r.ok)return 0;bytes=new Uint8Array(await r.arrayBuffer());}catch(_){return 0;}
  var at=0;function line(){var end=bytes.indexOf(10,at);if(end<0)throw Error('Bad settings bundle');var s=new TextDecoder().decode(bytes.subarray(at,end));at=end+1;return s;}
  if(line()!=='CHEZWEB-SETTINGS 1')return 0;
  function clear(path){try{if(FS.isDir(FS.stat(path).mode)){FS.readdir(path).forEach(n=>{if(n!=='.'&&n!=='..')clear(path+'/'+n);});FS.rmdir(path);}else FS.unlink(path);}catch(_){}}
  clear(base+'/languages');clear(base+'/extensions');clear(base+'/init.scm');
  var count=0;Module.chezwebLoading=true;
  try{while(at<bytes.length){
   var name=line(),n=Number(line());
   if(!/^(init\.scm|(languages|extensions)\/[^\/]+\.scm)$/.test(name)||!(n>=0)||at+n>bytes.length)throw Error('Bad settings bundle');
   var path=base+'/'+name;FS.mkdirTree(path.slice(0,path.lastIndexOf('/')));FS.writeFile(path,bytes.subarray(at,at+n));at+=n;count++;}}
  catch(e){notice('Your ~/.chezemax files were not loaded: '+e.message,true);}
  finally{Module.chezwebLoading=false;}
  return count;
 }
 // Your compiled scripts (chezemax --compile-scripts), from the native
 // window's server: put in the browser's ~/.chezemax/chezemax.wasm, dated
 // after Chezweb's own, or before it when yours are older (then empty).
 // The C start-up (src/compiled-program.c) then chooses as in the terminal:
 // yours when not older and they start, else Chezweb's own, and says why.
 async function program(){
  var r;try{r=await fetch('program',{cache:'no-store'});}catch(_){return;}
  if(!r.ok)return;
  var older=r.headers.get('X-Chezweb-Program')==='older',bytes=new Uint8Array(await r.arrayBuffer()),dir='/home/web_user/.chezemax',path=dir+'/chezemax.wasm';
  // Chezweb's own (/chezemax.wasm) is dated when the page starts: a day
  // later than that, or earlier, puts yours on the right side of it.
  var when=Date.now()+(older?-1:1)*86400000;FS.mkdirTree(dir);Module.chezwebLoading=true;
  try{FS.writeFile(path,older?new Uint8Array(0):bytes);FS.utime(path,when,when);}
  catch(e){notice('Your compiled scripts were not used: '+e.message,true);try{FS.unlink(path);}catch(_){}}
  finally{Module.chezwebLoading=false;}
 }
 async function init(){
  if(typeof WebAssembly.Suspending!=='function'||typeof WebAssembly.promising!=='function')throw new Error('Chezweb requires Chrome with WebAssembly JSPI. Update Chrome and reopen this page.');
  canvas=document.getElementById('screen');ctx=canvas.getContext('2d');keys=document.getElementById('keys');layout();
  document.addEventListener('keydown',key,true);keys.addEventListener('input',e=>{if(!e.isComposing){text(keys.value);keys.value='';}});keys.addEventListener('compositionend',()=>{text(keys.value);keys.value='';});
  document.addEventListener('paste',e=>{var s=e.clipboardData.getData('text/plain');if(s){e.preventDefault();var p=stringToNewUTF8(s);Module._web_set_scrap(p);text('\x19');}});
  function mouse(e,button,release){var box=canvas.getBoundingClientRect(),col=Math.floor((e.clientX-box.left-pad)/cw),row=Math.floor((e.clientY-box.top-pad)/ch);col=Math.max(0,Math.min(cols-1,col));row=Math.max(0,Math.min(rows-1,row));text('\x1b[<'+button+';'+(col+1)+';'+(row+1)+(release?'m':'M'));}
  var dragging=false;canvas.addEventListener('mousedown',e=>{if(e.button===0){keys.focus();dragging=true;mouse(e,0,false);e.preventDefault();}});window.addEventListener('mouseup',e=>{if(dragging){dragging=false;mouse(e,0,true);}});window.addEventListener('mousemove',e=>{if(dragging)mouse(e,32,false);else mouse(e,35,false);});canvas.addEventListener('wheel',e=>{e.preventDefault();mouse(e,e.deltaY<0?64:65,false);},{passive:false});
  window.addEventListener('resize',()=>{layout();push(154);});keys.focus();
  FS.mkdirTree('/home/web_user');FS.chdir('/home/web_user');ENV.HOME='/home/web_user';await settings();await program();
  var initial='Welcome to Chezweb.\n\nC-x C-f opens files. C-x C-s saves.\nAsk Codex or Claude in your terminal or SDL window.\n';
  try{var r=await fetch('session',{cache:'no-store'});if(r.ok){initial=await r.text();Module.chezwebSession=true;}}catch(_){}
  var name='browser.txt';try{var nr=await fetch('name',{cache:'no-store'});if(nr.ok){var value=await nr.text();if(value&&!/[\/\\\x00-\x1f]/.test(value))name=value;}}catch(_){}
  Module.chezwebSessionPath='/home/web_user/'+name;FS.writeFile(Module.chezwebSessionPath,initial);
  // Only explicitly closed write streams on the session file are returned
  // to the native editor. Ordinary typing, listing and startup never save.
  var close=FS.close;FS.close=function(stream){var save=!Module.chezwebLoading&&Module.chezwebSession&&stream.path===Module.chezwebSessionPath&&(stream.flags&3)!==0;var result=close(stream);if(save){var body=FS.readFile(stream.path);Module.chezwebSave=fetch('session',{method:'PUT',headers:{'Content-Type':'application/x-chezweb-text'},body}).then(r=>{if(!r.ok)throw Error('Native window rejected save');notice('Saved to the native window. Return there and press a key to import it.');}).catch(e=>notice(e.message,true));}return result;};
  document.getElementById('grammarly-toggle').onclick=()=>{evals.push('(toggle-grammarly)');push(-2);keys.focus();};
  document.getElementById('choose-folder').onclick=async()=>{try{var path=await ChezwebFiles.pickDirectory();var shown=await ChezwebShell.selectDirectory(path);notice('Current directory: '+shown);}catch(e){if(e.name==='AbortError')notice('Folder selection cancelled.');else notice(e.message,true);}finally{keys.focus();}};
  document.getElementById('open-file').onclick=async()=>{try{var handles=await window.showOpenFilePicker(),h=handles[0],f=await h.getFile(),path='/home/web_user/'+f.name;var bytes=new Uint8Array(await f.arrayBuffer());Module.chezwebLoading=true;try{FS.writeFile(path,bytes);}finally{Module.chezwebLoading=false;}Module.chezwebHandles=Module.chezwebHandles||new Map();Module.chezwebHandles.set(path,h);evals.push('(find-file '+JSON.stringify(path)+')');push(-2);keys.focus();}catch(e){if(e.name!=='AbortError')notice(e.message,true);}};
  ChezwebFiles.install();
  var originalClose=FS.close;FS.close=function(stream){var path=stream.path,h=ChezwebFiles.target(path),save=h&&!Module.chezwebLoading&&(stream.flags&3)!==0,result=originalClose(stream);if(save){var bytes=FS.readFile(path);Module.chezwebSave=(async()=>{await ChezwebFiles.write(path,bytes);notice('File saved.');})().catch(e=>notice(e.message,true));}return result;};
  document.getElementById('starting').hidden=true;
 }
 async function end(){
  if(ended)return;
  ended=true;
  ChezwebGrammar.update(null);
  // Let an explicitly requested save finish before the page disappears.
  await Module.chezwebSave;
  window.close();
  if(!window.closed)notice('Chezweb browser editor closed. Your native window remains open. You can close this tab.',true);
 }
 function notice(s,bad){var el=document.getElementById('notice');clearTimeout(noticeTimer);el.textContent=s||'';el.title=s||'';el.hidden=!s;el.className=bad?'failure':'';if(s&&!bad)noticeTimer=setTimeout(()=>{el.hidden=true;},4500);}
 Module.preRun=Module.preRun||[];Module.preRun.push(()=>{addRunDependency('chezweb-page');init().then(()=>removeRunDependency('chezweb-page')).catch(e=>{notice(e.message,true);});});
 return {textLayer:json=>ChezwebGrammar.update(json),layerGeometry:()=>({cw,ch,pad,points,cols,top:canvas.getBoundingClientRect().top}),sendText:text,queueScheme:s=>{evals.push(s);push(-2);},isEnded:()=>ended,rows:()=>rows,settings,cols:()=>cols,paint,nextByte:()=>queue.length?Promise.resolve(queue.shift()):new Promise(r=>{waiter=r;}),takeEval:()=>evals.length?evals.shift():null,flushInput:()=>{queue=[];},copy:s=>navigator.clipboard.writeText(s).catch(()=>{}),paste:async()=>{try{return await navigator.clipboard.readText();}catch(_){return null;}},font:(f,p)=>{if(p>0)points=p;layout();},setOption:()=>{},ended:end,notice};
})();
Module.onAbort=e=>Module.browsered.notice('Chezweb failed: '+e,true);
