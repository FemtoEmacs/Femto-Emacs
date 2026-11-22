// One tab per file (21 November 2026).  Two tabs that edit the same file
// lose work: the second C-x C-s replaces the first without a question.  So
// a tab claims each file it opens with Chrome's Web Locks, and a second tab
// is refused the file.  Chrome releases a tab's locks when the tab closes,
// reloads or crashes: no lock is ever left behind to be cleared by hand.
//
// A lock has a name, and the same file can have different names in two
// tabs (two folders granted under different names), while two different
// files can have the same one (README.md picked in two tabs).  So the lock
// names a file by its base name only, and the tabs compare the files
// themselves: one asks the tab holding the name, over a BroadcastChannel,
// whether its file is the same entry (FileSystemHandle.isSameEntry).  A
// different file takes the next free name (README.md#2).  The asking is
// done under one more lock, chezweb-claims, so that two tabs opening the
// same file at the same moment cannot both find it free.  A tab that does
// not answer within two seconds counts as holding the file: refusing is
// safe, opening might not be.  The native file of C-c d is named by its
// path on disk, which the page knows (GET target).
var ChezwebClaims=(function(){
 'use strict';
 var held=new Map(),byPath=new Map(),waiting=new Map(),tab=Math.random().toString(36).slice(2)+Date.now().toString(36),serial=0;
 var channel=typeof BroadcastChannel==='function'?new BroadcastChannel('chezweb-claims'):null;
 function base(file){return file.native?'chezweb-native\n'+file.native:'chezweb-file\n'+file.path.slice(file.path.lastIndexOf('/')+1);}
 async function same(a,b){
  if(a.native||b.native)return a.native===b.native;
  if(a.handle&&b.handle&&a.handle.isSameEntry){try{return await a.handle.isSameEntry(b.handle);}catch(_){}}
  return a.path===b.path;
 }
 function shown(path){return path.startsWith('/home/web_user/')?'~'+path.slice(14):path;}
 if(channel)channel.onmessage=async e=>{
  var m=e.data;if(!m||m.to&&m.to!==tab)return;
  if(m.type==='reply'){var w=waiting.get(m.id);if(w){waiting.delete(m.id);w(m.same);}return;}
  if(m.type!=='ask')return;
  var mine=held.get(m.name);if(!mine)return;
  var answer=await same(mine,{path:m.path,native:m.native,handle:m.handle});
  channel.postMessage({type:'reply',to:m.from,id:m.id,same:answer});
  if(answer&&Module.browsered)Module.browsered.notice('Another tab asked to open '+(mine.native||shown(mine.path))+'. It stays open here; close this tab to open it there.',false,true);
 };
 function ask(name,file){
  if(!channel)return Promise.resolve(null);
  var id=tab+':'+(++serial);
  return new Promise(resolve=>{
   waiting.set(id,resolve);
   var m={type:'ask',from:tab,id,name,path:file.path,native:file.native||null,handle:file.handle||null};
   try{channel.postMessage(m);}catch(_){m.handle=null;channel.postMessage(m);}   // a handle that cannot be sent
   setTimeout(()=>{if(waiting.has(id)){waiting.delete(id);resolve(null);}},2000);
  });
 }
 function acquire(name){
  return new Promise(resolve=>{
   navigator.locks.request(name,{ifAvailable:true},lock=>{if(!lock){resolve(null);return;}return new Promise(release=>resolve(release));});
  });
 }
 // Claim FILE ({path, handle, native}) for this tab: null when it is ours,
 // else the reason another tab has it.
 async function claim(file){
  if(!navigator.locks)return null;          // no Web Locks: the save check (ChezwebFiles.write) remains
  if(byPath.has(file.path))return null;
  var stem=base(file);
  return await navigator.locks.request('chezweb-claims',async()=>{
   var state=await navigator.locks.query(),names=new Set();
   for(var l of state.held)if(l.name===stem||l.name.startsWith(stem+'#'))names.add(l.name);
   for(var name of names){
    var mine=held.get(name);
    if(mine){if(await same(mine,file)){byPath.set(file.path,name);return null;}continue;}
    var answer=await ask(name,file);
    if(answer===true)return (file.native||shown(file.path))+' is open in another Chezweb tab. Close that tab to open it here.';
    if(answer!==false)return (file.native||shown(file.path))+' may be open in another Chezweb tab that does not answer. Close that tab to open it here.';
   }
   for(var i=1;;i++){
    var name=i===1?stem:stem+'#'+i;if(names.has(name))continue;
    var release=await acquire(name);
    if(release){held.set(name,{path:file.path,native:file.native||null,handle:file.handle||null,release});byPath.set(file.path,name);return null;}
   }
  });
 }
 return {claim,claimed:path=>byPath.has(path)};
})();

// Chrome folder grants, adapted from Browsered's lazy filesystem adapter.
// Only a directory's immediate children are listed; listing/opening never
// creates or writes a file on the computer. The C prompt remains unchanged.
var ChezwebFiles=(function(){
 'use strict';
 var home='/home/web_user',folders=new Map(),directories=new Map(),listed=new Set(),busy=false;
 // The date and size of each file as this tab last read or wrote it: a
 // save checks them first (write, below).
 var seen=new Map();
 function remember(path,file){seen.set(path,{time:file.lastModified,size:file.size});}
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
     if(!FS.analyzePath(child).exists){Module.chezwebLoading=true;try{FS.writeFile(child,new Uint8Array(0));}finally{Module.chezwebLoading=false;}var node=FS.lookupPath(child).node;node.chezwebFile=file;node.usedBytes=file.size;node.timestamp=file.lastModified;remember(child,file);}
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
 // The folders a typed path names, outermost first: the first COUNT of its
 // components (all of them if COUNT is omitted).  Below ~ every one may be
 // granted; elsewhere only those the browser does not already have.
 function candidates(path,count){
  var top=path.startsWith(home+'/')?home:'',parts=path.slice(top.length+1).split('/').filter(Boolean),out=[],at=top;
  if(count!==undefined)parts=parts.slice(0,count);
  for(var part of parts){at+='/'+part;if(top||!FS.analyzePath(at).exists)out.push(at);}
  return out;
 }
 function shown(path){return path.startsWith(home+'/')?'~'+path.slice(home.length):path;}
 // Chrome tells a page a folder's name, never where it is.  For a typed path
 // (~/mysand/chezmoi/or) any folder the path names will do -- mysand or
 // chezmoi -- and is mapped where the path puts it (~/mysand/chezmoi), so
 // the next TAB completes inside it instead of asking again.
 async function pickDirectory(requested){
  if(!window.showDirectoryPicker)throw Error('Choose a folder using Google Chrome.');
  var bases=typeof requested==='string'?candidates(requested):requested||[];
  var names=bases.map(b=>b.slice(b.lastIndexOf('/')+1)).reverse();
  names=names.filter((n,i)=>names.indexOf(n)===i);
  var wanted=names.length===1?names[0]:names.slice(0,-1).join(', ')+' or '+names[names.length-1];
  Module.browsered.notice(names.length?'Choose the '+wanted+' folder, or use Choose folder to select another.':'Choose any directory you want to use.');
  var handle=await window.showDirectoryPicker({id:'chezweb',mode:'readwrite'});
  if(!names.length)return await grant(handle);
  var base=null;for(var b of bases)if(b.slice(b.lastIndexOf('/')+1)===handle.name)base=b;   // the deepest
  if(!base)throw Error('That path needs the '+wanted+' folder, not '+handle.name+'. To use '+handle.name+' itself, choose it with Choose folder or cd --pick: it becomes ~/'+handle.name+'/.');
  return await grant(handle,base);
 }
 async function choose(path,bases){
  await pickDirectory(bases);
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
  if(!folder&&path===home){
   // At ~/ the first Tab grants a local folder, whichever the user picks.
   if(partial&&folders.size===0){await pickDirectory();folder=folderOf(path);}
  }else if(!folder&&path.startsWith(home+'/')){
   // Browser-internal paths keep ordinary completion.  A path whose folders
   // the browser does not have yet asks for one of them; a single unknown
   // name being completed at ~/ asks for any folder.
   var parts=path.slice(home.length+1).split('/'),count=typed.endsWith('/')?parts.length:parts.length-1;
   var bases=candidates(path,count);
   if(count===0){if(partial&&!FS.readdir(home).some(name=>name.startsWith(parts[0]))){await pickDirectory();folder=folderOf(path);}}
   else if(bases.some(b=>!FS.analyzePath(b).exists))folder=await choose(path,bases);
  }
  if(!folder)return true;
  var parts=path.slice(folder.base.length).split('/').filter(Boolean),at=folder.base;
  await list(folder.handle,at);
  for(var i=0;i<parts.length-1;i++){
   at+='/'+parts[i];var dir=directories.get(at);if(!dir)break;await list(dir,at);
  }
  // A trailing slash in a Tab prompt means complete inside this directory.
  if(partial&&typed.endsWith('/')&&directories.has(path))await list(directories.get(path),path);
  // A file (an existing one, or a new one in a granted folder) is this
  // tab's only, or the prompt is refused (ChezwebClaims, above).
  // (A file of the browser's own temporary storage belongs to this tab
  // anyway, and is not claimed.)
  if(!partial&&!directories.has(path)&&(handles().has(path)||(folder&&!FS.analyzePath(path).exists))){
   var refused=await ChezwebClaims.claim({path,handle:handles().get(path)||null});
   if(refused){Module.browsered.notice(refused,true);return false;}
  }
  if(!partial&&handles().has(path)){
   var file=await handles().get(path).getFile(),bytes=new Uint8Array(await file.arrayBuffer());
   Module.chezwebLoading=true;try{FS.writeFile(path,bytes);delete FS.lookupPath(path).node.chezwebFile;}finally{Module.chezwebLoading=false;}
   remember(path,file);
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
    // Opened without a prompt (a buffer list, a script): claimed now, in the
    // background; a save waits for the claim (page.js).
    if(node&&handles().has(path)&&!ChezwebClaims.claimed(path))
     ChezwebClaims.claim({path,handle:handles().get(path)}).then(r=>{if(r)Module.browsered.notice(r,true);});
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
  // As the native C-x C-s does, never write over a change made since this
  // tab read the file: another tab, another program.  Nothing is written,
  // and the buffer stays modified (page.js), so no text is lost.
  var before=seen.get(path),now=null;
  try{now=await handle.getFile();}catch(_){}
  if(before&&now&&(now.lastModified!==before.time||now.size!==before.size))
   throw Error(shown(path)+' changed on disk since this tab read it, and was not saved. C-x C-w saves your text under another name.');
  if(!before&&now&&now.size>0)
   throw Error(shown(path)+' was created on disk by another program meanwhile, and was not saved. C-x C-w saves your text under another name.');
  var writable=await handle.createWritable();await writable.write(bytes);await writable.close();
  try{remember(path,await handle.getFile());}catch(_){seen.delete(path);}
 }
 return {
  install,write,normalize,remember,pickDirectory,prepareListing,readDirectory:directory,
  target:path=>handles().has(path)||!!folderOf(normalize(path)),
  describe(path){
   path=normalize(path);var folder=folderOf(path),handle=handles().get(path);
   if(folder)return (path.startsWith(home+'/')?'~'+path.slice(home.length):path)+' (chosen folder)';
   return handle?'selected file '+(handle.name||path.slice(path.lastIndexOf('/')+1)):path;
  },
  async prepare(typed,partial){if(busy)return false;busy=true;try{return await prepare(typed,partial);}catch(e){if(e.name!=='AbortError')Module.browsered.notice(e.message,true);return false;}finally{busy=false;}}
 };
})();
