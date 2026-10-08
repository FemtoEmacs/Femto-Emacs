# Python-mode oracle for the synpy Lisp backend

`../languages/python.synpy` is a Python-style editor extension, not a
line-by-line translation of `python.lisp`. It contains an editor lexer,
a `PythonMode` class, pure indentation/coloring algorithms, definition
navigation commands and a Python-specific mode-line menu. Its hand-written
Common Lisp implementation in `../modes/python-mode.lisp` is now the startup
default. The old script is archived in `../modes/legacy/python.lisp`.
`M-x python-mode` can reload and reactivate the standard mode. This implementation uses the source as a specification, and
does not require the future synpy compiler or a Python interpreter.
See `../modes/README.md` for loading instructions.

## Current behavior

* Highlights Python keywords, `async`/`await`, definition names, decorators,
  call-position builtins, decimal/base-prefixed numbers, comments, string
  prefixes and triple-quoted strings.
* Recognizes `match`/`case` as soft keywords in colon-terminated headers,
  rather than highlighting variables named `match` or `case`. Also has
  heuristic recognition of `type` alias headers.
* Colors f-string interpolation expressions separately from literal text,
  including escaped braces and nested replacement fields in format specs.
* Tolerates incomplete strings and expressions while the user types.
* Writes one face per UTF-8 **byte**, including multilingual names and
  text; navigation also uses editor byte offsets.
* Indents suites by four spaces, aligns continuation arguments, uses a
  hanging indent after an otherwise empty opening bracket, and aligns a
  closing bracket with its opening line's indentation.
* Handles explicit backslash continuations, comments, CRLF, tab stops,
  `async` compound statements, `elif`, `else`, `except*`, `finally`, and
  `match`/`case`. Preserves multiline-string body indentation.
* Provides repeated-TAB alternatives because source alone cannot always
  establish whether the author intends to end a suite.
* Adds IND, #, DEF> and <DEF buttons for `.py`, `.pyw`,
  `.pyi` and `.synpy` buffers. It keeps the previous menu's actions and
  returns its original menu for other files. Navigation skips apparent
  definitions inside strings and comments.

The mode reuses existing face IDs and user-selected colors; it does not
reconfigure the global theme. No menu action runs a Python program or
changes a whole buffer automatically.

## Library bridge required by the backend

The imports are logical modules for SBEmacs's libraries, not imports of
Python packages at editor runtime. The test harness supplies Python
adapters. **These adapters do not constitute a working Lisp backend.**

| Python-facing interface | Existing SBEmacs interface / required adaptation |
|---|---|
| `highlight.define_language(name, ..., highlighter=fn)` | `define-language`, with keyword argument names converted to Lisp hyphenated keywords and the compiled function supplied as `:highlighter` |
| `theme.color_id("keyword")` | `color-id :keyword` in `ffi.lisp`; exported through the theme facade, not a new face system |
| `indent.define_indentation(...)` | `define-indentation`; convert the style name to a Lisp keyword and callback options to function designators |
| `context.text`, `.line`, `.width` | `ictx-text`, `ictx-line`, `ictx-width`; line is a byte offset |
| `editor.buffer_octets`, `buffer_size`, `point`, `goto_char`, `message` | Corresponding functions in SBEmacs, with underscores mapped to hyphens |
| `editor.call_in_window_of`, `buffer_filename` | Existing functions; the former is currently in `extensions/assistant.lisp` and must be available before this mode is installed |
| `editor.register_command(fn)` | `register-command` takes a **symbol**, not a callable object; the bridge must associate the compiled function with an editor command symbol |
| Menu `(label, callable)` entries | Existing menu action symbols; convert registered callables to their command symbols. Key-string actions pass through unchanged. |

Three convenience bridge operations are proposed; they are **not** existing
Lisp functions in the original API. The hand-written mode now implements
style registration directly and uses `install-mode-menu` from the optional
mode loader for owner-based menu contributions. A future synpy compiler
still needs the following Python-facing facade:

* `indent.register_style(name, callback, scan_from_start=True)` registers a
  compiled callback in `*indent-styles*`, as `define-indent-style` does.
  It must unwrap the context and supply a start-line predicate that always
  returns NIL. Existing `buffer-indent-context` then expands its search
  back to the start of the buffer; do not mistake this for the absence of
  a predicate, which enables the bounded-context default.
* `menu.base_buttons_provider(owner)` returns the provider that preceded
  this extension, without stacking the extension on top of itself when
  scripts reload.
* `menu.install_buttons_provider(owner, fn)` updates
  `*mode-line-buttons-function*` and records ownership for safe reloads.
  It retains the previous provider used above. Existing buffer-specific
  menus and help-window hints keep their normal precedence.

The highlighter callback has the existing `(language text length colors)`
shape. The byte-vector and color-vector adapters must provide byte access
and indexed writes without copying color changes away from C's output.
The indentation callback returns a nonnegative column or NIL to leave the
line untouched. Test Python `None` models that NIL result, separately from
column zero.

The compiler will also need the syntax exercised here: imports, classes,
instance attributes and methods, comprehensions, sets/dictionaries,
sequence slices, loops, exceptions-free calls, default/keyword arguments,
and the small set of string/byte operations used by the lexer. Their
compiled semantics must be specified against these oracle tests instead
of assuming arbitrary Python runtime compatibility.

## Validation

```sh
python3 lisp/py2sexpr/test_python_mode.py
python3 lisp/py2sexpr/test_py2sexpr.py
python3 lisp/py2sexpr/test_lisp_python_mode.py
python3 lisp/py2sexpr/py2sexpr.py --locations \
    lisp/languages/python.synpy -o python-mode.sexpr
```

The mode suite executes the source with isolated editor-library adapters.
It checks algorithms and registration requests, not the C GUI. Selected
string and numeric token boundaries are compared with Python's standard
`tokenize` module. The complete mode AST has also been read by real SBCL.
The differential suite runs the actual Lisp implementation in SBCL and
compares full byte-color arrays and indentation columns against fixtures
collected from these tests, plus three complete Python source files. It
also calls the foreign-callable C highlighting entry point with pinned
buffers. Loader registration, menu ownership, navigation and activation
without a source directory are checked independently. A terminal SBEmacs
session has also exercised `M-x load-mode`, menu rendering and navigation.
This is a hand-written reference backend, not automatically generated Lisp.

## Known limits and next oracles

This is an editor lexer/indenter, not Python's full parser or a scope
analyzer. Builtin coloring does not resolve shadowed bindings. Soft-keyword
recognition is heuristic, including physical-line header recognition.
F-string cases supported by Python 3.12's relaxed grammar (such as reusing
the outer quote inside a replacement expression) need additional lexer
state and tests. Existing highlighting passes bounded preceding context;
a triple string starting before that context needs a cache or a larger
context strategy in the eventual bridge. Indentation deliberately scans
from the start for correctness; large-buffer incremental caching is a
subsequent optimization. Blank-line suite termination remains ambiguous,
so TAB cycling is kept.

These limits are explicit: passing the Python oracle suite is not proof
of complete Python grammar coverage or of a synpy-to-Lisp compiler.
The optional hand-written Lisp mode and its SBEmacs menu are now implemented.
