"""Dependency-free tests; SBCL reader integration is required, not mocked."""
import ast
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import py2sexpr as p

HERE = Path(__file__).resolve().parent
K = p.keyword


class SyntaxTests(unittest.TestCase):
    def test_named_fields_and_precedence(self):
        data = p.ast_data(ast.parse("x = 1 + 2 * 3"))
        assignment = data[2][0]
        expression = dict(zip(assignment[1::2], assignment[2::2]))[K("value")]
        fields = dict(zip(expression[1::2], expression[2::2]))
        self.assertEqual(fields[K("op")], (K("Add"),))
        multiplication = dict(zip(fields[K("right")][1::2], fields[K("right")][2::2]))
        self.assertEqual(multiplication[K("op")], (K("Mult"),))

    def test_falsy_literals_remain_distinct(self):
        values = [0, False, None, "", b"", Ellipsis]
        self.assertEqual(len({p.render(p.literal_data(v), False) for v in values}), len(values))
        self.assertEqual(p.literal_data(0), (K("integer"), K("value"), 0))
        self.assertEqual(p.literal_data(False), (K("boolean"), K("value"), K("false")))

    def test_float_and_complex_exact_encoding(self):
        for value in [0.0, -0.0, 0.1, 1e300, float("inf")]:
            representation = p.literal_data(value)
            self.assertEqual(representation[2], value.hex())
        self.assertEqual(p.literal_data(2j)[0], K("complex"))

    def test_controls_and_surrogates_are_explicit(self):
        self.assertEqual(p.text_data("\n\t\x00\ud800"),
                         (K("text-codepoints"), K("values"), (10, 9, 0, 55296)))
        self.assertEqual(p.literal_data(b"\x00\xff"), (K("bytes"), K("octets"), (0, 255)))

    def test_source_is_never_executed(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "never-created"
            p.convert("from pathlib import Path\nPath(%r).write_text('executed')" % str(target))
            self.assertFalse(target.exists())

    def test_multiline_string_and_blank_lines(self):
        source = '\n\nx = """first  \n\nlast   """\n'
        tree = p.ast_data(ast.parse(source), locations=True)
        text = p.render(tree)
        self.assertIn("(102 105 114 115 116 32 32 10 10 108 97 115 116 32 32 32)", text)
        self.assertIn(":line 3", text)

    def test_locations_and_utf8_byte_columns(self):
        source = "é = 0; x = 1\n"
        tree = p.ast_data(ast.parse(source), locations=True)
        fields = dict(zip(tree[2][1][1::2], tree[2][1][2::2]))
        location = dict(zip(fields[K("source")][::2], fields[K("source")][1::2]))
        self.assertEqual(location[K("column")], 8)  # é occupies two UTF-8 bytes.
        self.assertNotIn(":source", p.convert(source))

    def test_type_annotations_and_type_comments(self):
        output = p.convert("def café(x: int) -> str:\n    y = x # type: int\n    return '你好'\n")
        self.assertIn(":annotation", output)
        self.assertIn(":returns", output)
        self.assertIn(':type-comment "int"', output)
        self.assertIn('"café"', output)

    def test_richer_ast_is_not_silently_dropped(self):
        source = "@decorate\nasync def f(x, /, *, limit=2):\n    return [a for a in x if a < limit]\n"
        output = p.convert(source)
        for token in [":async-function-def", ":decorator-list", ":posonlyargs", ":kwonlyargs", ":list-comp"]:
            self.assertIn(token, output)

    def test_integer_conversion_has_no_decimal_output_limit(self):
        value = 1 << 20000
        text = p.decimal(value)
        self.assertGreater(len(text), 5000)
        # Avoid int(text), which may itself have a configured digit limit.
        rebuilt = 0
        for start in range(0, len(text), 9):
            chunk = text[start:start + 9]
            rebuilt = rebuilt * 10 ** len(chunk) + int(chunk)
        self.assertEqual(rebuilt, value)

    def test_detected_source_encodings(self):
        self.assertEqual(p.decode_source(b"\xef\xbb\xbfx=0"), "x=0")
        self.assertEqual(p.decode_source(b"# coding: latin-1\nx='caf\xe9'"), "# coding: latin-1\nx='café'")
        with self.assertRaises((UnicodeError, SyntaxError)):
            p.decode_source(b"x='\xff'")


class CommandTests(unittest.TestCase):
    def command(self, *args, source=b""):
        return subprocess.run([sys.executable, str(HERE / "py2sexpr.py"), *args],
                              input=source, capture_output=True)

    def test_cli_stdout_is_utf8_not_console_encoding(self):
        result = self.command(source="x='你好 français 한국어 𒀭𒂗𒆤'".encode())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("你好 français 한국어 𒀭𒂗𒆤", result.stdout.decode("utf-8"))
        self.assertFalse(result.stderr)

    def test_syntax_error_has_location_and_no_partial_output(self):
        result = self.command(source=b"\n\ndef broken(:\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(result.stdout)
        self.assertIn(b"<stdin>:3:", result.stderr)

    def test_file_output_is_preserved_on_invalid_input(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "out.sexpr"
            output.write_text("keep this", encoding="utf-8")
            result = self.command("-o", str(output), source=b"def broken(:")
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_text(), "keep this")
            result = self.command("--compact", "-o", str(output), source=b"x=0")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(output.read_text().splitlines()), 1)

    def test_missing_file_is_an_error(self):
        with tempfile.TemporaryDirectory() as folder:
            result = self.command(str(Path(folder) / "missing.py"))
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(result.stdout)


class LispReaderTests(unittest.TestCase):
    def test_actual_sbcl_reader_and_lossless_literals(self):
        sbcl = shutil.which("sbcl")
        self.assertIsNotNone(sbcl, "Install SBCL to run reader interoperability tests")
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            for pretty in (True, False):
                fixtures = ["ação français 中文 한국어 𒀭𒂗𒆤", "", "\n\t\x00\r\\\"", "#.(error \"NEVER EXECUTE\")"]
                for i, text in enumerate(fixtures):
                    (folder / ("literal-%d.sexpr" % i)).write_text(p.convert("x = " + repr(text), pretty=pretty), encoding="utf-8")
                (folder / "mixed.sexpr").write_text(p.convert("x=0\ny=False\nz=None\nb=b'\\x00\\xff'\nf=0.1\nc=2j\ne=...", pretty=pretty), encoding="utf-8")
                program = r'''
(setf sb-impl::*default-external-format* :utf-8)
(defun read-ast (file)
  (let ((*read-eval* nil))
    (with-open-file (in file :external-format :utf-8)
      (let ((form (read in)))
        (assert (eq (car form) :py2sexpr))
        (assert (= (getf (cdr form) :format-version) 1))
        (assert (eq (read in nil :eof) :eof))
        (getf (cdr form) :tree)))))
(defun values-of (tree)
  (mapcar (lambda (statement) (getf (cdr (getf (cdr statement) :value)) :value))
          (getf (cdr tree) :body)))
(defun text-value (literal)
  (let ((v (getf (cdr literal) :value)))
    (if (stringp v) v (coerce (mapcar #'code-char (getf (cdr v) :values)) 'string))))
(assert (string= (text-value (first (values-of (read-ast "literal-0.sexpr"))))
                 "ação français 中文 한국어 𒀭𒂗𒆤"))
(assert (string= (text-value (first (values-of (read-ast "literal-1.sexpr")))) ""))
(assert (equal (map 'list #'char-code (text-value (first (values-of (read-ast "literal-2.sexpr")))))
               '(10 9 0 13 92 34)))
(assert (search "#.(error" (text-value (first (values-of (read-ast "literal-3.sexpr"))))))
(let ((v (values-of (read-ast "mixed.sexpr"))))
  (assert (equal (mapcar #'car v) '(:integer :boolean :none :bytes :float :complex :ellipsis)))
  (assert (= (getf (cdr (first v)) :value) 0))
  (assert (eq (getf (cdr (second v)) :value) :false))
  (assert (equal (getf (cdr (fourth v)) :octets) '(0 255)))
  (assert (string= (getf (cdr (fifth v)) :hex) "0x1.999999999999ap-4")))
(format t "SBCL reader: exact multilingual text and typed literals verified.~%")
'''
                script = folder / "reader-test.lisp"
                script.write_text(program, encoding="utf-8")
                result = subprocess.run([sbcl, "--noinform", "--no-sysinit", "--no-userinit", "--script", str(script)],
                                        cwd=folder, capture_output=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout.decode(errors="replace") + result.stderr.decode(errors="replace"))
                self.assertIn(b"verified", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
