# py2sexpr: Python syntax as S-expression data

This is the first stage of a Python-syntax-to-Common-Lisp tool for SBEmacs.
Python parses the source; this program emits a named-field abstract syntax
tree that Common Lisp can read. It does **not** execute Python, generate
executable Lisp, implement Python semantics, or load an editor extension.
Those belong to the subsequent Common Lisp compiler.

The implementation uses only Python's standard library and requires Python
3.9 or later. Accepted syntax is the grammar of the Python interpreter
running it. SBCL is required for the reader interoperability tests.

## Run

From the SBEmacs repository:

```sh
python3 lisp/py2sexpr/py2sexpr.py extension.py -o extension.sexpr
python3 lisp/py2sexpr/py2sexpr.py --locations extension.py -o extension.sexpr
python3 lisp/py2sexpr/py2sexpr.py --compact < extension.py > extension.sexpr
```

On Windows, `py -3` can be used instead of `python3`. Prefer `-o` there:
this writes UTF-8 directly and avoids shell-dependent redirection encodings.
Stdin and stdout remain supported; stdout is explicitly UTF-8.

There is no `make` step for this standalone frontend. Merely placing this
folder inside `lisp/` does not connect it to SBEmacs's extension loader.

## Output contract: format version 1

The output is exactly one Common Lisp-readable data form, followed by a
newline. It contains a versioned envelope:

```lisp
(:py2sexpr
  :format-version 1
  :python-version "3.9"
  :filename "extension.py"
  :tree
  (:module
    :body
    ((:assign
       :targets ((:name :id "x" :ctx (:store)))
       :value (:constant :value (:integer :value 0) :kind :none)
       :type-comment :none))
    :type-ignores ()))
```

That example represents `x = 0`. Whitespace layout is not part of the
contract; `--compact` emits the same data on one line.

* AST node names and field names are keywords, converted from Python names
  to lowercase hyphenated names: `FunctionDef` becomes `:function-def`, and
  `type_comment` becomes `:type-comment`.
* A node has the shape `(:node-name :field value ...)`. All fields reported
  by `ast.iter_fields` are retained, including empty lists and optional
  fields. Consumers must use named fields rather than assume positions.
* Identifier spellings remain strings. The Lisp compiler decides how names
  become symbols and which package owns them.
* AST sequences are lists. An empty sequence is `()`. An absent scalar field
  is `:none`, so the two remain distinguishable.
* Structural integer fields remain integers; structural boolean fields are
  `:true` or `:false`.
* Python's AST schema can change between versions. `:python-version`
  records the parser's major/minor version. The envelope version describes
  our serialization contract, not a promise that all Python versions have
  identical AST fields. A future backend should check supported grammar
  versions and explicitly reject unsupported nodes.

### Literal values

A `:constant` node's `:value` is explicitly typed:

| Source value | Literal data |
|---|---|
| `0` | `(:integer :value 0)` |
| `False` | `(:boolean :value :false)` |
| `True` | `(:boolean :value :true)` |
| `None` | `(:none)` |
| `...` | `(:ellipsis)` |
| `""` | `(:string :value "")` |
| `"你好 한국어 français 𒀭"` | `(:string :value "你好 한국어 français 𒀭")` |
| `0.1` | `(:float :hex "0x1.999999999999ap-4")` |
| `2j` | `(:complex :real (:float :hex "0x0.0p+0") :imag (:float :hex "0x1.0000000000000p+1"))` |
| `b"\x00\xff"` | `(:bytes :octets (0 255))` |
| `"a\n"` | `(:string :value (:text-codepoints :values (97 10)))` |

Float hex strings preserve the Python parser's exact binary float value.
They are data, not Common Lisp numeric syntax. Nonfinite parser values use
`"inf"`, `"-inf"` or `"nan"`; the later compiler must decide whether to
accept them. Negative expressions such as `-0.0` retain the AST unary
operator rather than being folded by this tool.

String quotes and backslashes are escaped using Common Lisp reader rules.
Python escapes such as `\n`, `\x00` and `\u1234` are never emitted as if the
Lisp reader interpreted them. Strings containing control characters or
surrogate code points instead use `:text-codepoints`, preserving every
value numerically. This encoding also applies to textual AST fields or
filenames when needed. Surrogates remain data; consumers must not silently
replace them with other characters.

Chinese, French, Korean and cuneiform text are preserved exactly. Unicode
normalization is not applied: decomposed and precomposed text remain
distinct. Preserving cuneiform characters is separate from understanding
or translating Sumerian.

### Locations

`--locations` adds `:source` to AST nodes that have line information:

```lisp
:source (:line 3 :column 0 :end-line 3 :end-column 8)
```

Lines are one-based. Columns are zero-based UTF-8 **byte offsets**, as
specified by Python's AST, not character counts or screen columns. Missing
end positions are `:none`. The original input is not stripped or filtered:
blank lines and string whitespace survive the parser input.

Syntax errors use `filename:line:column: message` on stderr and a nonzero
exit status. The displayed syntax-error column follows Python's own
`SyntaxError.offset`; do not confuse it with the AST's byte offsets.
No AST is emitted after a parse error. With `-o`, an existing output file is
replaced atomically only after successful parsing and serialization.
Source decoding honors Python encoding declarations and UTF-8 BOMs.

## Reading from Common Lisp

Read the output as data, with reader evaluation disabled, then check the
envelope and reject additional forms. For example, in SBCL:

```lisp
(let ((*read-eval* nil))
  (with-open-file (input "extension.sexpr" :external-format :utf-8)
    (let ((form (read input)))
      (assert (eq (first form) :py2sexpr))
      (assert (eql (getf (rest form) :format-version) 1))
      (assert (eq (read input nil :eof) :eof))
      (getf (rest form) :tree))))
```

Do not `load` or `eval` this AST. It is input data for the subsequent Lisp
compiler. `ast.parse` also does not enforce every compilation-context rule
(for example, whether a `return` is inside a function); the later compiler
must diagnose those according to our language's semantics.

Ordinary comments and exact source formatting are not represented by the
AST. Docstrings, type annotations, type comments and type-ignore records
are retained. If comment-preserving editing is needed later, it requires
an additional token/source layer, not invented AST nodes.

## Test

```sh
python3 lisp/py2sexpr/test_py2sexpr.py
```

The suite uses `unittest` and a real SBCL subprocess. It checks named
fields and precedence; distinct zero/false/none/empty values; annotations;
source spans; multiline strings; encodings; file and stdin operation;
invalid input; exact Unicode; bytes, float and complex representations;
large integer serialization; and Common Lisp reader compatibility for
both pretty and compact output. It also verifies that parsing a program
does not execute its file-writing statements. No third-party packages are
needed.

## References

* [Python AST](https://docs.python.org/3/library/ast.html)
* [Python source encoding detection](https://docs.python.org/3/library/tokenize.html#tokenize.detect_encoding)

This tool develops the AST-printing approach of `py2noL.py`, replacing its
old `compiler` interface, anonymous child printing, input filtering and
loss of false-valued literals. It deliberately stops before semantic
translation into Common Lisp.
