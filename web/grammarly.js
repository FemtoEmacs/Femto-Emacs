// Browsered's on-demand text overlay. The compiled editor owns all edits.
var ChezwebGrammar=(function(){
 'use strict';
 var layer=null,info=null,shadow='',typing=false,composing=false,pending=0;
 function remove(){if(!layer)return;var focused=document.activeElement===layer;layer.remove();layer=null;info=null;if(focused)document.getElementById('keys').focus({preventScroll:true});}
 function index(text,offset){var bytes=0,i=0;while(i<text.length&&bytes<offset){var cp=text.codePointAt(i);bytes+=cp<128?1:cp<2048?2:cp<65536?3:4;i+=cp>65535?2:1;}return i;}
 function caret(){var at=index(shadow,info.point);layer.setSelectionRange(at,at);layer.scrollTop=0;layer.scrollLeft=0;}
 function input(){
  var now=layer.value,old=shadow,typed=typing;typing=false;if(now===old)return;
  var p=0,n=Math.min(now.length,old.length);while(p<n&&now.charCodeAt(p)===old.charCodeAt(p))p++;
  if(p>0&&now.charCodeAt(p-1)>=0xD800&&now.charCodeAt(p-1)<=0xDBFF)p--;
  var q=0;while(q<n-p&&now.charCodeAt(now.length-1-q)===old.charCodeAt(old.length-1-q))q++;
  if(q>0&&now.charCodeAt(now.length-q)>=0xDC00&&now.charCodeAt(now.length-q)<=0xDFFF)q--;
  var added=now.slice(p,now.length-q).replace(/\r\n?/g,'\n'),removed=old.slice(p,old.length-q);
  if(!removed&&p===index(old,info.point))typed=true;
  if(typed){layer.value=old;caret();if(added)Module.browsered.sendText(added);return;}
  shadow=now;pending++;
  Module.browsered.queueScheme('(web-layer-edit '+JSON.stringify(info.buffer)+' '+info.page+' '+lengthBytesUTF8(old.slice(0,p))+' '+JSON.stringify(removed)+' '+JSON.stringify(added)+')');
 }
 function make(){
  var t=document.createElement('textarea');t.id='text-layer';t.setAttribute('aria-label','Buffer text for Grammarly');t.spellcheck=true;
  // Do not set data-gramm, autocomplete or hidden: Grammarly ignores those.
  t.addEventListener('keydown',e=>{if(!e.ctrlKey&&!e.metaKey&&!e.altKey&&(e.key.length===1||e.key==='Dead'||e.key==='Process'))typing=true;});
  t.addEventListener('keyup',()=>{if(!composing)typing=false;});
  t.addEventListener('compositionstart',()=>{composing=true;typing=true;});
  t.addEventListener('compositionend',()=>{composing=false;input();});
  t.addEventListener('input',e=>{if(!e.isComposing&&!composing)input();});
  t.addEventListener('mousedown',e=>{if(e.button===0)document.getElementById('screen').dispatchEvent(new MouseEvent('mousedown',{clientX:e.clientX,clientY:e.clientY,button:0}));});
  t.addEventListener('wheel',e=>{e.preventDefault();document.getElementById('screen').dispatchEvent(new WheelEvent('wheel',{clientX:e.clientX,clientY:e.clientY,deltaY:e.deltaY}));},{passive:false});
  document.body.appendChild(t);return t;
 }
 function update(json){
  var on=!!Module._web_layer_on()&&!Module.browsered.isEnded(),button=document.getElementById('grammarly-toggle');
  button.textContent='Grammarly: '+(on?'on':'off');button.setAttribute('aria-pressed',String(on));
  if(!json||!on){remove();return;}
  try{
   var next=JSON.parse(json);if(!layer)layer=make();var g=Module.browsered.layerGeometry(),s=layer.style;
   s.left=g.pad+'px';s.top=(g.top+g.pad+next.top*g.ch)+'px';s.width=(g.cols*g.cw+.5)+'px';s.height=(next.rows*g.ch)+'px';
   s.font=g.points+'px Menlo,Consolas,monospace';s.lineHeight=g.ch+'px';info=next;
   if(pending||composing)return;
   if(layer.value!==next.text)layer.value=next.text;shadow=next.text;caret();
   if(document.activeElement.id==='keys'||document.activeElement===document.body)layer.focus({preventScroll:true});
  }catch(e){Module._web_layer_set(0);remove();Module.browsered.notice('Grammarly field closed: '+e.message,true);}
 }
 return {update,applied:ok=>{pending=Math.max(0,pending-1);if(!ok){Module._web_layer_set(0);remove();}}};
})();
