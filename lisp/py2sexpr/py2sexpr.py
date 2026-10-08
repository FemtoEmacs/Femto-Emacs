#!/usr/bin/env python3
"""Serialize Python syntax as Common Lisp-readable data; never execute it."""
import argparse
import ast
import io
import os
from pathlib import Path
import re
import sys
import tempfile
import tokenize
from dataclasses import dataclass

FORMAT_VERSION = 1


@dataclass(frozen=True)
class Keyword:
    name: str


def keyword(name):
    """Only serializer-controlled names can become Lisp symbols."""
    name = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1-\2", name)
    name = re.sub(r"([a-z0-9])([A-Z])", r"\1-\2", name)
    name = name.replace("_", "-").lower()
    if not re.fullmatch(r"[a-z][a-z0-9-]*", name):
        raise ValueError("Invalid AST field or node name: " + name)
    return Keyword(name)


def text_data(value):
    # Common Lisp does not interpret Python's \n, \u or \x escapes.
    # Keep readable text literal; encode controls/surrogates as numeric data.
    if any(ord(c) < 32 or ord(c) == 127 or 0xD800 <= ord(c) <= 0xDFFF for c in value):
        return (keyword("text-codepoints"), keyword("values"), tuple(map(ord, value)))
    return value


def literal_data(value):
    if value is None:
        return (keyword("none"),)
    if value is Ellipsis:
        return (keyword("ellipsis"),)
    if isinstance(value, bool):  # bool subclasses int; test it first.
        return (keyword("boolean"), keyword("value"), keyword("true" if value else "false"))
    if isinstance(value, int):
        return (keyword("integer"), keyword("value"), value)
    if isinstance(value, float):
        # Exact binary value, including negative zero; no Python repr in Lisp.
        return (keyword("float"), keyword("hex"), value.hex())
    if isinstance(value, complex):
        return (keyword("complex"), keyword("real"), literal_data(value.real),
                keyword("imag"), literal_data(value.imag))
    if isinstance(value, str):
        return (keyword("string"), keyword("value"), text_data(value))
    if isinstance(value, bytes):
        return (keyword("bytes"), keyword("octets"), tuple(value))
    raise TypeError("Unsupported AST literal type: " + type(value).__name__)


def ast_data(value, locations=False):
    if isinstance(value, ast.AST):
        fields = [keyword(type(value).__name__)]
        for name, child in ast.iter_fields(value):
            fields.extend((keyword(name), literal_data(child) if isinstance(value, ast.Constant)
                           and name == "value" else ast_data(child, locations)))
        if locations and hasattr(value, "lineno"):
            location = []
            for attribute, label in (("lineno", "line"), ("col_offset", "column"),
                                     ("end_lineno", "end-line"), ("end_col_offset", "end-column")):
                location.extend((keyword(label), ast_data(getattr(value, attribute, None))))
            fields.extend((keyword("source"), tuple(location)))
        return tuple(fields)
    if isinstance(value, (list, tuple)):
        return tuple(ast_data(child, locations) for child in value)
    if value is None:
        return keyword("none")
    if isinstance(value, bool):
        return keyword("true" if value else "false")
    if isinstance(value, str):
        return text_data(value)
    if isinstance(value, int):
        return value
    raise TypeError("Unsupported AST field type: " + type(value).__name__)


def decimal(value):
    # Chunk conversion also supports huge Python integers when the host limits
    # int-to-decimal string conversion (e.g. a large hexadecimal source literal).
    sign = "-" if value < 0 else ""
    value = abs(value)
    chunks = []
    while value >= 1000000000:
        value, chunk = divmod(value, 1000000000)
        chunks.append(chunk)
    return sign + str(value) + "".join("%09d" % c for c in reversed(chunks))


def render(value, pretty=True, indent=0):
    if isinstance(value, Keyword):
        return ":" + value.name
    if isinstance(value, str):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(value, int):
        return decimal(value)
    if not isinstance(value, tuple):
        raise TypeError("Unserializable data type: " + type(value).__name__)
    if not value:
        return "()"
    if not pretty or not any(isinstance(item, tuple) and item for item in value):
        return "(" + " ".join(render(item, False) for item in value) + ")"
    # AST nodes and the envelope are tagged property lists.
    if isinstance(value[0], Keyword) and len(value) % 2 == 1 and all(
            isinstance(value[i], Keyword) for i in range(1, len(value), 2)):
        pad = " " * (indent + 2)
        return "(" + render(value[0]) + "\n" + "\n".join(
            pad + render(value[i]) + " " + render(value[i + 1], True, indent + 2)
            for i in range(1, len(value), 2)) + ")"
    pad = " " * (indent + 2)
    return "(\n" + "\n".join(pad + render(item, True, indent + 2) for item in value) + ")"


def convert(source, filename="<stdin>", locations=False, pretty=True):
    """Parse only. The later Lisp compiler decides semantics and valid contexts."""
    tree = ast.parse(source, filename=filename, mode="exec", type_comments=True)
    envelope = (keyword("py2sexpr"), keyword("format-version"), FORMAT_VERSION,
                keyword("python-version"), "%d.%d" % sys.version_info[:2],
                keyword("filename"), text_data(filename), keyword("tree"), ast_data(tree, locations))
    return render(envelope, pretty) + "\n"


def decode_source(raw):
    encoding, _ = tokenize.detect_encoding(io.BytesIO(raw).readline)
    return raw.decode(encoding)


def write_atomic(path, output):
    path = Path(path)
    name = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="\n",
                                         dir=path.parent, delete=False) as stream:
            name = stream.name
            stream.write(output)
        os.replace(name, path)
        name = None
    finally:
        if name is not None:
            os.unlink(name)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", default="-", help="Python file, or - for stdin")
    parser.add_argument("-o", "--output", help="S-expression file; default: stdout")
    parser.add_argument("--locations", action="store_true", help="include original source spans")
    parser.add_argument("--compact", action="store_true", help="write one line instead of indented forms")
    options = parser.parse_args(argv)
    filename = "<stdin>" if options.input == "-" else options.input
    try:
        raw = sys.stdin.buffer.read() if options.input == "-" else Path(options.input).read_bytes()
        output = convert(decode_source(raw), filename, options.locations, not options.compact)
        if options.output:
            write_atomic(options.output, output)
        else:
            # Explicit UTF-8 works even in a Windows OEM-codepage console.
            sys.stdout.buffer.write(output.encode("utf-8"))
        return 0
    except SyntaxError as error:
        print("%s:%s:%s: %s" % (error.filename or filename, error.lineno or 1,
                                 error.offset or 1, error.msg), file=sys.stderr)
    except (OSError, UnicodeError, ValueError, TypeError, RecursionError) as error:
        print("py2sexpr: %s: %s" % (filename, error), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
