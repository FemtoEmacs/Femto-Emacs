// Chrome folder grants, adapted from Browsered's lazy filesystem adapter.
// Only a directory's immediate children are listed; listing/opening never
// creates or writes a file on the computer. The C prompt remains unchanged.
var ChezwebFiles=(function(){
 'use strict';
 var home='/home/web_user',folders=new Map(),directories=new Map(),listed=new Set(),busy=false;
 function normalize(path){
  if(path==='~')path=home;else if(path.startsWith('~/'))path=home+path.slice(1);
  if(!path.startsWith('/'))path=FS.cwd()+'/'+path;
  var out=[];for(var part of path.split('/')){if(!part||part==='.')continue;if(part==='..')out.pop();else out.push(part);}
  return '/'+out.join('/');
 }
 function folderOf(path){var best=null;for(var [base,handle] of folders)if((path===base||path.startsWith(base+'/'))&&(!best||base.length>best.base.length))best={base,handle};return best;}
 function handles(){return Module.chezwebHandles||(Module.chezwebHandles=new Map());}
 async function list(handle,path){
  if(listed.has(path))return;
  FS.mkdirTree(path);
  {
   for await(var entry of handle.values()){
    var child=path+'/'+entry.name;
    if(entry.kind==='directory'){FS.mkdirTree(child);directories.set(child,entry);}
    else {
     // Keep File metadata, not its contents. Large files cost no read here.
     var file=await entry.getFile();handles().set(child,entry);
     if(!FS.analyzePath(child).exists){Module.chezwebLoading=true;try{FS.writeFile(child,new Uint8Array(0));}finally{Module.chezwebLoading=false;}var node=FS.lookupPath(child).node;node.chezwebFile=file;node.usedBytes=file.size;node.timestamp=file.lastModified;}
    }
   }
   listed.add(path);
  }
 }
 // A browser handle has a name, not an absolute native path. Explicit
 // picking uses that name under ~/; typed paths are aliases the user chose.
 // Never replace an existing grant with a different folder of the same name.
 async function grant(handle,base){
  if(!base){
   var stem=home+'/'+(handle.name||'folder');base=stem;var suffix=2;
   while(FS.analyzePath(base).exists){
    var old=folders.get(base);
    if(old&&(old===handle||(handle.isSameEntry&&await handle.isSameEntry(old))))return base;
    base=stem+'-'+suffix++;
   }
  }
  if(FS.analyzePath(base).exists&&!FS.isDir(FS.stat(base).mode))throw Error('That name is already used by a browser file.');
  folders.set(base,handle);directories.set(base,handle);await list(handle,base);
  Module.browsered.notice('Folder available as '+(base.startsWith(home+'/')?'~'+base.slice(home.length):base)+'/');
  return base;
 }
 async function pickDirectory(requested){
  if(!window.showDirectoryPicker)throw Error('Choose a folder using Google Chrome.');
  var expected=requested?requested.slice(requested.lastIndexOf('/')+1):'';
  Module.browsered.notice(expected?'Choose the '+expected+' directory, or use Choose folder to select another.':'Choose any directory you want to use.');
  var handle=await window.showDirectoryPicker({id:'chezweb',mode:'readwrite'});
  if(expected&&handle.name!==expected)throw Error('Select '+expected+' for that path, or use Choose folder / cd --pick to select '+handle.name+'.');
  return await grant(handle,requested);
 }
 async function choose(path,partial,typed){
  var first=path.slice(home.length+1).split('/')[0];
  var single=partial&&!typed.endsWith('/')&&path.slice(home.length+1).indexOf('/')<0;
  if(single||!first){await pickDirectory();}else{await pickDirectory(home+'/'+first);}
  return folderOf(path);
 }
 async function directory(path){
  path=normalize(path);
  if(folderOf(path)){
   if(!await prepare(path+'/',true))throw Error('No folder was selected');
  }else if(!FS.analyzePath(path).exists){
   await pickDirectory(path);
  }
  if(!FS.isDir(FS.stat(path).mode))throw Error('Not a directory: '+path);
  return FS.readdir(path);
 }
 async function prepareListing(path){
  path=normalize(path);
  if(folderOf(path))await prepare(path,true);
  else if(!FS.analyzePath(path).exists)await directory(path);
 }
 async function prepare(typed,partial){
  var path=normalize(typed),folder=folderOf(path);
  if(!folder){
   // Browser-internal paths keep ordinary completion. At ~/ the first
   // Tab grants a local folder; an unknown ~/folder/... requests that root.
   var root=path.slice(home.length+1).split('/')[0];
   var tail=path.slice(home.length+1);
   var knownPrefix=partial&&!typed.endsWith('/')&&FS.readdir(home).some(name=>name.startsWith(root));
   var missingRoot=path.startsWith(home+'/')&&root&&!FS.analyzePath(home+'/'+root).exists&&(partial||tail.includes('/'))&&!knownPrefix;
   if((partial&&path===home&&folders.size===0)||missingRoot){folder=await choose(path,partial,typed);}
  }
  if(!folder)return true;
  var parts=path.slice(folder.base.length).split('/').filter(Boolean),at=folder.base;
  await list(folder.handle,at);
  for(var i=0;i<parts.length-1;i++){
   at+='/'+parts[i];var dir=directories.get(at);if(!dir)break;await list(dir,at);
  }
  // A trailing slash in a Tab prompt means complete inside this directory.
  if(partial&&typed.endsWith('/')&&directories.has(path))await list(directories.get(path),path);
  if(!partial&&handles().has(path)){
   var file=await handles().get(path).getFile(),bytes=new Uint8Array(await file.arrayBuffer());
   Module.chezwebLoading=true;try{FS.writeFile(path,bytes);delete FS.lookupPath(path).node.chezwebFile;}finally{Module.chezwebLoading=false;}
  }
  return true;
 }
 function load(node){
  var file=node.chezwebFile,url=URL.createObjectURL(file);
  try{
   var q=new XMLHttpRequest();q.open('GET',url,false);q.overrideMimeType('text/plain; charset=x-user-defined');q.send();
   if((q.status!==200&&q.status!==0)||q.responseText.length!==file.size)throw Error('The selected file could not be read. Select its folder again.');
   var bytes=new Uint8Array(file.size);for(var i=0;i<bytes.length;i++)bytes[i]=q.responseText.charCodeAt(i)&255;
   node.contents=bytes;node.usedBytes=bytes.length;delete node.chezwebFile;
  }finally{URL.revokeObjectURL(url);}
 }
 function install(){var open=FS.open;
  FS.open=function(path,flags){
   if(!Module.chezwebLoading&&typeof path==='string'){
    var mode=typeof flags==='string'?FS.modeStringToFlags(flags):flags,node;
    try{node=FS.lookupPath(path).node;}catch(_){}
    if(node&&node.chezwebFile){if(mode&512){node.contents=new Uint8Array(0);node.usedBytes=0;delete node.chezwebFile;}else load(node);}
   }
   return open.apply(this,arguments);
  };
 }
 async function write(path,bytes){
  path=normalize(path);var handle=handles().get(path),folder=folderOf(path);
  if(!handle&&folder){
   var parts=path.slice(folder.base.length+1).split('/'),dir=folder.handle;
   for(var i=0;i<parts.length-1;i++)dir=await dir.getDirectoryHandle(parts[i],{create:true});
   handle=await dir.getFileHandle(parts[parts.length-1],{create:true});handles().set(path,handle);
  }
  if(!handle)throw Error('No local folder was granted for this file.');
  var writable=await handle.createWritable();await writable.write(bytes);await writable.close();
 }
 return {
  install,write,normalize,pickDirectory,prepareListing,readDirectory:directory,
  target:path=>handles().has(path)||!!folderOf(normalize(path)),
  describe(path){
   path=normalize(path);var folder=folderOf(path),handle=handles().get(path);
   if(folder)return (path.startsWith(home+'/')?'~'+path.slice(home.length):path)+' (chosen folder)';
   return handle?'selected file '+(handle.name||path.slice(path.lastIndexOf('/')+1)):path;
  },
  async prepare(typed,partial){if(busy)return false;busy=true;try{return await prepare(typed,partial);}catch(e){if(e.name!=='AbortError')Module.browsered.notice(e.message,true);return false;}finally{busy=false;}}
 };
})();
