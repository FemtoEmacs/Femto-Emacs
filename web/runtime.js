// Host for the unchanged compiled Scheme program. Every suspension-capable
// Wasm boundary uses JSPI; no Asyncify stack or legacy retry exists here.
var ChezwebScheme={modules:new Map(),error:'',
 async open(bytes,id){
  var m={id,memory:new WebAssembly.Memory({initial:16}),output:'',valueText:''};
  m.host=schemerHost(s=>{m.output+=s;},{
   read:p=>{if(m.input!==undefined){if(p!==':schemer-request')throw Error('Compiler file access is restricted to its request');return m.input;}try{return FS.readFile(p,{encoding:'utf8'});}catch(_){return null;}},
   write:(p,s)=>{if(m.input!==undefined)throw Error('Compiler cannot write files');FS.writeFile(p,s);},exists:p=>m.input===undefined&&FS.analyzePath(p).exists,remove:p=>{if(m.input!==undefined)throw Error('Compiler cannot remove files');FS.unlink(p);}
  });
  m.host.imports.host.memory=m.memory;
  m.host.imports.host.editor=new WebAssembly.Suspending(async n=>{
   if(typeof n!=='number'){var p=stringToNewUTF8(m.host.toJS(n)),r;try{r=await Module._web_editor_request(id,p);}finally{_free(p);}var reply=UTF8ToString(r);_free(r);return m.host.fromJS(reply);}
   this.toC(m);
   var result=await Module._web_ccall(id,n);
   this.fromC(m);return result;
  });
  m.instance=(await WebAssembly.instantiate(bytes,m.host.imports)).instance;
  m.host.setInstance(m.instance);this.modules.set(id,m);
 },
 fromC(m){var n=Module._web_module_size(m.id),p=Module._web_module_buffer(m.id);new Uint8Array(m.memory.buffer).set(HEAPU8.subarray(p,p+n));},
 toC(m){var n=Module._web_module_size(m.id),p=Module._web_module_buffer(m.id);HEAPU8.set(new Uint8Array(m.memory.buffer,0,n),p);},
 diagnostic(id,e){var m=this.modules.get(id),s='';try{s=m.host.message(e)||'';}catch(_){}return s||m.output.replace(/^Error: /,'').trim()||String(e.message||e);},
 async run(id,invoke){var m=this.modules.get(id);m.output='';try{
  this.fromC(m);var value=await WebAssembly.promising(invoke?m.instance.exports.call0:m.instance.exports.main)(...(invoke?[m.value]:[]));
  if(!invoke)m.value=value;this.toC(m);m.host.flush();m.instance.exports.write(value);m.valueText=m.host.text();return 1;
 }catch(e){try{m.host.flush();}catch(_){}this.error=this.diagnostic(id,e);return 0;}},
 async call(id,a,b,c){var m=this.modules.get(id);this.fromC(m);try{return await WebAssembly.promising(m.instance.exports.call3)(m.value,a,b,c);}finally{this.toC(m);}}
};
