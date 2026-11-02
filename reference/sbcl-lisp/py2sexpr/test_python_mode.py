"""Executable Python oracle for python.synpy; editor adapters are test doubles."""
import ast
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import tokenize
import types
import unittest

HERE = Path(__file__).resolve().parent
MODE_FILE = HERE.parent / "languages" / "python.synpy"
FACES = {"alpha": 5, "keyword": 4, "digits": 6, "comment": 7, "string": 9,
         "symbol": 1, "heading": 11, "emphasis": 12, "link": 14}


def load_mode(path):
    records = {}
    common = [("HELP", "C-h"), ("SAVE", "C-x C-s"), ("UNDO", "C-/")]
    modules = {}
    for name in ("highlight", "indent", "theme", "menu", "editor"):
        modules[name] = types.ModuleType(name)
    modules["theme"].color_id = lambda name: FACES[name]
    modules["highlight"].define_language = lambda name, **options: records.update(language=(name, options))
    modules["indent"].register_style = lambda name, callback, **options: records.update(style=(name, callback, options))
    modules["indent"].define_indentation = lambda name, **options: records.update(indentation=(name, options))
    modules["menu"].base_buttons_provider = lambda owner: (lambda buffer: common)
    modules["menu"].install_full_buttons_provider = lambda owner, provider: records.update(full_menu=(owner, provider))
    modules["menu"].full_buttons = lambda buffer: common
    modules["menu"].install_buttons_provider = lambda owner, provider: records.update(menu=(owner, provider))
    modules["editor"].register_command = lambda function: records.setdefault("commands", []).append(function)
    modules["editor"].call_in_window_of = lambda name, function: function()
    modules["editor"].buffer_filename = lambda: records.get("filename", "example.py")
    modules["editor"].buffer_octets = lambda start, end: records["source"][start:end]
    modules["editor"].buffer_size = lambda: len(records["source"])
    modules["editor"].point = lambda: records.get("point", 0)
    modules["editor"].goto_char = lambda position: records.update(point=position)
    modules["editor"].message = lambda text: records.update(message=text)
    previous = {name: sys.modules.get(name) for name in modules}
    try:
        sys.modules.update(modules)
        namespace = {"__name__": "python_mode"}
        exec(compile(path.read_text(encoding="utf-8"), str(path), "exec"), namespace)
    finally:
        for name, old in previous.items():
            if old is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = old
    return types.SimpleNamespace(**namespace), records, common


class ModeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module, cls.records, cls.common = load_mode(MODE_FILE)
        cls.mode = cls.module.MODE

    def faces(self, source):
        raw = source.encode("utf-8")
        colors = [0] * len(raw)
        self.mode.colorize(None, raw, len(raw), colors)
        return raw, colors

    def face_of(self, source, part):
        raw, colors = self.faces(source)
        start = raw.index(part.encode("utf-8"))
        return colors[start:start + len(part.encode("utf-8"))]

    def indent(self, prefix, line=""):
        text = (prefix + line).encode("utf-8")
        return self.mode.indent_line(types.SimpleNamespace(text=text, line=len(prefix.encode("utf-8")), width=4))

    def test_keywords_definitions_and_unicode_byte_alignment(self):
        source = "async def café(名字):\n    return '한국어 𒀭' # français\n"
        for part, face in [("async", "keyword"), ("def", "keyword"), ("café", "heading"),
                           ("return", "keyword"), ("'한국어 𒀭'", "string"), ("# français", "comment")]:
            self.assertEqual(self.face_of(source, part), [FACES[face]] * len(part.encode()))
        self.assertEqual(len(self.faces(source)[1]), len(source.encode()))

    def test_strings_prefixes_escapes_comments_and_partial_triples(self):
        source = 'x = r"# raw\\\\"\ny = b"bytes"\nz = """first\n# inside\nlast"""\n'
        tokens = self.module.lex(source)
        strings = [t.value for t in tokens if t.kind == "string"]
        oracle = [t.string for t in tokenize.generate_tokens(io.StringIO(source).readline) if t.type == tokenize.STRING]
        self.assertEqual(strings, oracle)
        self.assertFalse(any(t.kind == "comment" for t in tokens))
        partial = self.module.lex('doc = """not closed\n')[-1]
        self.assertFalse(partial.closed)

    def test_numeric_literals_match_python_tokenizer(self):
        source = "x = 0xff + 0b1010 + 0o755 + 1_000 + .5 + 1.5e-3 + 2j\n"
        ours = [t.value for t in self.module.lex(source) if t.kind == "number"]
        oracle = [t.string for t in tokenize.generate_tokens(io.StringIO(source).readline) if t.type == tokenize.NUMBER]
        self.assertEqual(ours, oracle)

    def test_fstring_expressions_and_nested_format_fields(self):
        source = 'x = f"{{literal}} {len(items):{width}.{precision}f}"\n'
        self.assertEqual(self.face_of(source, "len"), [FACES["emphasis"]] * 3)
        self.assertEqual(self.face_of(source, "items"), [FACES["alpha"]] * 5)
        self.assertEqual(self.face_of(source, "width"), [FACES["alpha"]] * 5)
        self.assertEqual(self.face_of(source, "{{literal}}"), [FACES["string"]] * 11)

    def test_decorators_and_builtin_calls_not_attributes(self):
        source = "@functools.cache\ndef f():\n    print(obj.print())\n"
        self.assertEqual(self.face_of(source, "functools"), [FACES["link"]] * 9)
        raw, colors = self.faces(source)
        positions = [i for i in range(len(raw)) if raw.startswith(b"print", i)]
        self.assertEqual(colors[positions[0]], FACES["emphasis"])
        self.assertEqual(colors[positions[1]], FACES["alpha"])

    def test_soft_keywords_are_contextual(self):
        for source in ("match = 1\n", "case = 2\n", "type = 3\n", "obj.match()\n"):
            word = "match" if "match" in source else "case" if "case" in source else "type"
            self.assertEqual(self.face_of(source, word), [FACES["alpha"]] * len(word))
        for source, word in [("match subject:\n", "match"), ("    case [x, y]:\n", "case"), ("type Alias = list[int]\n", "type")]:
            self.assertEqual(self.face_of(source, word), [FACES["keyword"]] * len(word))

    def test_nested_blocks_async_and_decorators(self):
        self.assertEqual(self.indent("async def f():\n"), 4)
        self.assertEqual(self.indent("def f():\n    if ready:\n"), 8)
        self.assertEqual(self.indent("@decorate\n"), 0)
        self.assertEqual(self.indent("def f():\n    # comment with colon:\n"), 4)

    def test_bracket_alignment_hanging_indents_and_closers(self):
        self.assertEqual(self.indent("value = call(first,\n"), 13)
        self.assertEqual(self.indent("value = call(   first,\n"), 16)
        self.assertEqual(self.indent("value = call(\n"), 4)
        self.assertEqual(self.indent("value = call(\n    first,\n", ")"), 0)
        self.assertEqual(self.indent("def f():\n    values = [\n"), 8)

    def test_ignore_brackets_and_colons_in_comments_and_strings(self):
        self.assertEqual(self.indent('x = "[(not code):" # {\n'), 0)
        self.assertEqual(self.indent('def f():\n    text = """first\n    second\n'), None)
        self.assertEqual(self.indent('def f():\n    text = """first\n    second\n    """\n'), 4)

    def test_elif_else_except_star_and_finally_alignment(self):
        self.assertEqual(self.indent("if ready:\n    work()\n", "else:"), 0)
        self.assertEqual(self.indent("if ready:\n    if nested:\n        work()\n", "else:"), 4)
        self.assertEqual(self.indent("try:\n    work()\n", "except* Error:"), 0)
        self.assertEqual(self.indent("try:\n    work()\nexcept Error:\n    recover()\n", "finally:"), 0)

    def test_match_case_and_terminal_statements(self):
        self.assertEqual(self.indent("match value:\n", "case 1:"), 4)
        self.assertEqual(self.indent("match value:\n    case 1:\n        handle()\n", "case 2:"), 4)
        self.assertEqual(self.indent("def f():\n    if x:\n        return x\n"), 4)
        self.assertEqual(self.indent("return x\n"), 0)
        self.assertEqual(self.indent("match value:\n    case 1:\n        handle()\n", "case = 2"), 8)
        self.assertEqual(self.indent("async def f():\n    async for item in items:\n        handle(item)\n", "else:"), 4)

    def test_explicit_continuations_crlf_and_tabs(self):
        self.assertEqual(self.indent("x = first + \\\n"), 4)
        self.assertEqual(self.indent("if ready:\r\n"), 4)
        self.assertEqual(self.indent("if ready:\n\twork()\n"), 8)

    def test_utf8_byte_line_positions(self):
        self.assertEqual(self.indent("变量 = '𒀭'\nif ready:\n"), 4)

    def test_tab_cycles_valid_columns(self):
        context = types.SimpleNamespace(text=b"if x:\n", line=6, width=4)
        self.assertEqual(self.mode.indentation_levels(context), [0, 4, 8])

    def test_registration_matches_callback_contract(self):
        self.assertEqual(self.records["language"][1]["extensions"], [".py", ".pyw", ".pyi", ".synpy"])
        self.assertEqual(self.records["style"][2], {"scan_from_start": True})
        self.assertEqual(self.records["indentation"][1]["width"], 4)
        self.assertFalse(self.records["indentation"][1]["tabs"])
        self.assertEqual(len(self.records["commands"]), 2)

    def test_menu_is_python_specific_and_keeps_common_actions(self):
        self.records["filename"] = "example.py"
        buttons = self.module.python_menu("example")
        self.assertTrue(all(item in buttons for item in self.common))
        self.assertIn(("#", "M-;"), buttons)
        self.assertIn(("INDENT", "menu-indent"), self.module.python_full_menu("example"))
        self.records["filename"] = "example.lisp"
        self.assertEqual(self.module.python_menu("example"), self.common)
        self.records["filename"] = "example.py"

    def test_navigation_ignores_fake_definitions_inside_strings(self):
        source = '变量 = 1\ntext = """\ndef fake():\n"""\nasync def real():\n    pass\nclass Other:\n    pass\n'
        self.records.update(source=source.encode(), point=0)
        self.module.next_definition()
        self.assertEqual(self.records["point"], len(source[:source.index("async def real")].encode()))
        self.module.next_definition()
        self.assertEqual(self.records["point"], len(source[:source.index("class Other")].encode()))
        self.module.previous_definition()
        self.assertEqual(self.records["point"], len(source[:source.index("async def real")].encode()))

    def test_ast_frontend_preserves_full_mode(self):
        sys.path.insert(0, str(HERE))
        import py2sexpr
        result = py2sexpr.convert(MODE_FILE.read_text(encoding="utf-8"), str(MODE_FILE), locations=True)
        self.assertIn(":class-def", result)
        self.assertIn(":import", result)
        self.assertIn(":function-def", result)
        self.assertIn("register_style", result)


if __name__ == "__main__":
    unittest.main(verbosity=2)
