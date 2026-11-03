// host.js -- what a module made by Schemer imports from JavaScript.
// Shared by the page (web/schemer.js) and node (run.js).
//
//   var host = schemerHost(function (text) { ... }, files, options);
//     FILES: see schemerMemoryFiles; OPTIONS.stop(seconds): true stops a
//     program still running after SECONDS (asked at 10 s, 20 s, 40 s...);
//     OPTIONS.editor(text) -> text: calls a procedure of the editor (see
//     %editor-apply in prelude.scm)
//   instance = (await WebAssembly.instantiate(bytes, host.imports)).instance;
//   host.setInstance(instance);
//   instance.exports.main();   // may throw host.Abort, RangeError, ...
//   host.flush();
"use strict";

function schemerFlonum(x) {
  if (x !== x) return "+nan.0";
  if (x === Infinity) return "+inf.0";
  if (x === -Infinity) return "-inf.0";
  if (Number.isInteger(x) && Math.abs(x) < 1e21) return (Object.is(x, -0) ? "-0" : x.toFixed(0)) + ".0";
  return String(x);
}

// FILES: {read(name) -> text or null, write(name, text), exists(name), remove(name)};
// by default, files in memory (lost when the page closes)
function schemerMemoryFiles() {
  var files = new Map();
  return {
    read: function (n) { return files.has(n) ? files.get(n) : null; },
    write: function (n, t) { files.set(n, t); },
    exists: function (n) { return files.has(n); },
    remove: function (n) { files.delete(n); }
  };
}

function schemerHost(write, files, options) {
  files = files || schemerMemoryFiles();
  options = options || {};
  var started = performance.now(), ask = 10;
  function Stopped(seconds) { this.seconds = seconds; }
  function toJS(s) {
    var x = instance.exports, n = x.string_length(s), r = "";
    for (var i = 0; i < n; i++) r += String.fromCodePoint(x.string_ref(s, i));
    return r;
  }
  function fromJS(t) {
    var cs = Array.from(t), x = instance.exports, s = x.string_new(cs.length);
    for (var i = 0; i < cs.length; i++) x.string_set(s, i, cs[i].codePointAt(0));
    return s;
  }
  var out = "", instance = null, number = "";
  var tables = new WeakMap(), symbols = new Map();
  function flush() { if (out) { write(out); out = ""; } }
  function Abort() {}
  var imports = { host: {
    write_char: function (c) { out += String.fromCodePoint(c); if (out.length > 65536) flush(); },
    write_flonum: function (x) { out += schemerFlonum(x); },
    flonum_char: function (x, i) { var s = schemerFlonum(x); return i < s.length ? s.charCodeAt(i) : -1; },
    abort: function () { throw new Abort(); },
    now: function () { return performance.now(); },
    math: function (op, x) { return [Math.exp, Math.log, Math.sin, Math.cos, Math.tan, Math.atan, Math.asin, Math.acos][op](x); },
    math2: function (op, x, y) { return [Math.pow, Math.atan2][op](x, y); },
    editor: function (s) {
      return fromJS(options.editor ? String(options.editor(toJS(s))) : "error there is no editor here");
    },
    poll: function () {
      var s = (performance.now() - started) / 1000;
      if (options.stop && s > ask) {
        if (options.stop(Math.round(s))) throw new Stopped(Math.round(s));
        ask = 2 * s;
      }
    },
    number_char: function (c) { number += String.fromCodePoint(c); },
    number_end: function () { var x = parseFloat(number); number = ""; return x; },
    file: function (op, name, data) {
      var n = toJS(name);
      switch (op) {
      case 0: var t = files.read(n); return t === null ? 0 : fromJS(t);
      case 1: files.write(n, toJS(data)); return 0;
      case 2: return files.exists(n) ? 1 : 0;
      case 3: files.remove(n); return 0;
      }
    },
    table: function (op, t, k, v) {
      var m = op >= 8 ? symbols : tables.get(t);
      switch (op) {
      case 0: tables.set(t, new Map()); return t;
      case 1: case 8: return m.has(k) ? m.get(k) : v;
      case 2: case 9: m.set(k, v); return v;
      case 3: m.delete(k); return v;
      case 4: return m.size;
      case 5: m.clear(); return v;
      case 6: m.forEach(function (x) { v = instance.exports.cons(x, v); }); return v;
      }
    },
  }};
  // WebAssembly's own errors, in Scheme's words
  function message(e) {
    if (e instanceof Stopped) return "stopped after " + e.seconds + " s";
    if (e instanceof RangeError) return "recursion too deep (the WebAssembly stack is full)";
    if (typeof WebAssembly.Exception !== "undefined" && e instanceof WebAssembly.Exception) return "a continuation called after its procedure returned (Schemer's continuations only escape)";
    var m = e.message;
    if (/illegal cast/.test(m)) return "a value of the wrong type (" + m + ")";
    if (/null/.test(m)) return "a variable used before it was given a value, or a wrong type (" + m + ")";
    if (/out of bounds/.test(m)) return "an index out of range (" + m + ")";
    return m;
  }
  return {
    imports: imports, flush: flush, Abort: Abort, message: message,
    toJS: toJS, fromJS: fromJS,
    setInstance: function (i) { instance = i; },
    text: function () { var t = out; out = ""; return t; }
  };
}

if (typeof module !== "undefined")
  module.exports = { schemerHost: schemerHost, schemerFlonum: schemerFlonum, schemerMemoryFiles: schemerMemoryFiles };
