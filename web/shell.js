// Limited browser command interpreter, adapted from Browsered. No process,
// network shell, eval, file write, redirection or expansion route exists.
var ChezwebShell=(function(){
 'use strict';
 const HOME='/home/web_user';
 var directory=null,previous=null,explicit=false;
  function shellWords(source) {
    var commands = [], words = [], word = "", started = false, quote = null;
    function finishWord() { if (started) { words.push(word); word = ""; started = false; } }
    function finishCommand(next) {
      finishWord();
      if (!words.length) throw new Error("Expected a command.");
      commands.push({words:words,next:next}); words = [];
    }
    source = source.replace(/^exec 2>&1\r?\n/, "").replace(/\\\r?\n/g, "");
    for (var i = 0; i < source.length; i++) {
      var ch = source[i];
      if (ch === "\\" && quote !== "'") {
        if (++i >= source.length) throw new Error("Incomplete escape.");
        word += source[i]; started = true;
      } else if (quote) {
        if (ch === quote) quote = null; else word += ch;
      } else if (ch === "'" || ch === '"') { quote = ch; started = true; }
      else if (/\s/.test(ch) && ch !== "\n") finishWord();
      else if (ch === ";" || ch === "\n") {
        finishWord(); if (words.length) finishCommand(";");
      } else if (ch === "&" && source[i + 1] === "&") { finishCommand("&&"); i++; }
      else if ("|&<>$`".indexOf(ch) >= 0) throw new Error("Pipes, redirection and expansion require the local shell.");
      else { word += ch; started = true; }
    }
    if (quote) throw new Error("Unclosed quote.");
    finishWord();
    if (words.length) finishCommand(null);
    else if (commands.length && commands[commands.length - 1].next === "&&") throw new Error("Expected a command after &&.");
    return commands;
  }

 function resolve(name,base){
  if(name==='~')name=HOME;else if(name.startsWith('~/'))name=HOME+name.slice(1);
  if(!name.startsWith('/'))name=base+'/'+name;
  var parts=[];for(var p of name.split('/')){if(p==='..')parts.pop();else if(p&&p!=='.')parts.push(p);}return '/'+parts.join('/');
 }
 function display(path){return path===HOME?'~':path.startsWith(HOME+'/')?'~'+path.slice(HOME.length):path;}
 function context(base){if(!explicit){directory=resolve(base||FS.cwd(),HOME);if(directory==='/')directory=HOME;}if(!directory)directory=FS.cwd();}
 async function read(path){return await ChezwebFiles.readDirectory(path);}
 async function run(command,base){
  context(base);var commands;try{commands=shellWords(command);}catch(e){return {output:'Browser commands: '+e.message+'\n',status:2,directory};}
  var output='',status=0,go=true;
  for(var step of commands){if(go){var args=step.words.slice(),name=args.shift();status=0;
   try{
    if(name==='help'){output+='Browser commands: ls [-ald] [path ...], cd [path|-], pwd, help. Use cd --pick, ls --pick, or Choose folder for any other directory.\nQuotes, ; and && are supported. Use the terminal or SDL window for a full shell.\n';}
    else if(name==='pwd'){if(args.length)throw Error('pwd takes no arguments');output+=display(directory)+'\n';}
    else if(name==='cd'){
     if(args.length>1)throw Error('cd takes one directory');
     var target=args[0]==='--pick'?await ChezwebFiles.pickDirectory():!args.length?HOME:args[0]==='-'?previous:resolve(args[0],directory);if(!target)throw Error('No previous directory');
     await read(target);FS.chdir(target);previous=directory;directory=FS.cwd();explicit=true;output+=display(directory)+'\n';
    }else if(name==='ls'){
     var all=false,long=false,only=false,pick=false,paths=[],options=true;
     for(var arg of args){if(options&&arg==='--')options=false;else if(options&&arg==='--pick')pick=true;else if(options&&arg.startsWith('-')&&arg.length>1){for(var flag of arg.slice(1)){if(flag==='a')all=true;else if(flag==='l')long=true;else if(flag==='d')only=true;else throw Error('unsupported ls option: -'+flag);}}else paths.push(arg);}
     if(pick){if(paths.length)throw Error('Use ls --pick without a path');paths=[await ChezwebFiles.pickDirectory()];}else if(!paths.length)paths=['.'];
     for(var part of paths){var at=resolve(part,directory);await ChezwebFiles.prepareListing(at);var stat=FS.stat(at),entries;
      if(FS.isDir(stat.mode)&&!only){entries=(await read(at)).filter(n=>all||!n.startsWith('.')).sort();if(paths.length>1)output+=display(at)+':\n';}else entries=[null];
      for(var entry of entries){var p=entry===null?at:at+'/'+entry,info=FS.stat(p),isdir=FS.isDir(info.mode),label=entry===null?part:entry;output+=(long?(isdir?'d ':'- ')+String(info.size).padStart(10)+' ':'')+label+(isdir?'/':'')+'\n';}
     }
    }else{status=127;output+=name+': not a browser command. Use ls, cd, pwd, or help; use the native window for a full shell.\n';}
   }catch(e){status=1;output+=name+': '+(e.message||String(e))+'\n';}
  }go=step.next!=='&&'||(go&&status===0);}
  return {output,status,directory};
 }
 async function complete(line){
  context(directory||FS.cwd());var start=0,segment=0,quote=null,escape=false;
  for(var i=0;i<line.length;i++){var ch=line[i];if(escape){escape=false;continue;}if(ch==='\\'&&quote!=="'"){escape=true;continue;}if(quote){if(ch===quote)quote=null;continue;}if(ch==='"'||ch==="'"){quote=ch;continue;}if(/\s/.test(ch))start=i+1;else if(ch===';'||ch==='&'){start=i+1;segment=start;}}
  var prefix=line.slice(0,start),raw=line.slice(start),token='',words;
  try{words=shellWords(line.slice(segment,start));var parsed=raw?shellWords(raw+(quote||'')):[];token=parsed.length?parsed[0].words[0]:'';}catch(_){return '';}
  if(!words.length)return ['cd','help','ls','pwd'].filter(n=>n.startsWith(token)).map(n=>prefix+n).join('\n');
  var command=words[words.length-1].words[0];if(['cd','ls'].includes(command)&&token.startsWith('--')&&'--pick'.startsWith(token))return prefix+'--pick';
  var only=command==='cd',slash=token.lastIndexOf('/'),folder=slash<0?'':token.slice(0,slash+1),stem=token.slice(slash+1),at=resolve(folder||'.',directory),entries;
  // As in C-x C-f: TAB at ~/ before any folder is granted asks for one.
  await ChezwebFiles.prepare(at+'/',true);
  try{entries=await read(at);}catch(_){return '';}
  return entries.filter(n=>n!=='.'&&n!=='..'&&!/[\r\n]/.test(n)&&n.startsWith(stem)&&(stem.startsWith('.')||!n.startsWith('.'))&&(!only||FS.isDir(FS.stat(at+'/'+n).mode))).sort().map(n=>{
   var value=folder+n+(FS.isDir(FS.stat(at+'/'+n).mode)?'/':'');
   return prefix+value.replace(/[\s'"\\;$&|<>`()*?!#[\]{}]/g,'\\$&');
  }).join('\n');
 }
 return {run,async selectDirectory(path){context(FS.cwd());await read(path);FS.chdir(path);previous=directory;directory=FS.cwd();explicit=true;return display(directory);},async request(name,arg){if(name==='grammarly-toggle'){Module._web_layer_set(!Module._web_layer_on());return 'ok';}if(name==='command-context'){context(arg);return 'ok';}if(name==='command-complete')return await complete(arg);if(name==='settings-reload')return String(await Module.browsered.settings());throw Error('Unknown browser command request');}};
})();
