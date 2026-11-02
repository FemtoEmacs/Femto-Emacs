"""Compare the actual SBCL mode with the executable Python specification.
Run from any directory; no third-party dependencies or Python runtime in editor.
"""
import io
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_python_mode import ModeTests, MODE_FILE, load_mode
from py2sexpr import render, keyword

ROOT = Path(__file__).resolve().parents[2]


def main():
    fixtures = []
    original_faces, original_indent = ModeTests.faces, ModeTests.indent

    def faces(self, source):
        result = original_faces(self, source)
        fixtures.append((keyword("colors"), source, tuple(result[1])))
        return result

    def indent(self, prefix, line=""):
        result = original_indent(self, prefix, line)
        fixtures.append((keyword("indent"), prefix, line, result if result is not None else ()))
        return result

    ModeTests.faces, ModeTests.indent = faces, indent
    try:
        result = unittest.TextTestRunner(stream=io.StringIO()).run(unittest.defaultTestLoader.loadTestsFromTestCase(ModeTests))
        if not result.wasSuccessful():
            raise AssertionError(result.errors + result.failures)
    finally:
        ModeTests.faces, ModeTests.indent = original_faces, original_indent
    module, _, _ = load_mode(MODE_FILE)
    # Real sizeable programs exercise token state across many lines.
    for path in (MODE_FILE, Path(__file__), Path(__file__).with_name("py2sexpr.py")):
        source = path.read_text(encoding="utf-8")
        raw = source.encode()
        colors = [0] * len(raw)
        module.MODE.colorize(None, raw, len(raw), colors)
        fixtures.append((keyword("colors"), source, tuple(colors)))
    with tempfile.TemporaryDirectory(prefix="sbemacs-python-mode-") as directory:
        path = Path(directory) / "oracle.sexpr"
        path.write_text(render(tuple(fixtures), pretty=False), encoding="utf-8")
        command = ["sbcl", "--noinform", "--non-interactive", "--no-sysinit", "--no-userinit",
                   "--load", str(ROOT / "tests/run-python-mode-tests.lisp")]
        import os
        # Model an upgrade that copied new scripts but left retired files.
        install_fixture = Path(directory) / "stale-install"
        (install_fixture / "languages").mkdir(parents=True)
        (install_fixture / "modes").mkdir()
        (install_fixture / "languages/python.lisp").write_text('(error "Stale Python script was loaded")', encoding="utf-8")
        (install_fixture / "languages/example.lisp").write_text('(in-package #:sbemacs)', encoding="utf-8")
        (install_fixture / "modes/python-mode.lisp").write_text('; Replacement exists', encoding="utf-8")
        old_fixture = Path(directory) / "old-install"
        (old_fixture / "languages").mkdir(parents=True)
        (old_fixture / "languages/python.lisp").write_text('; Legacy-only install', encoding="utf-8")
        environment = dict(os.environ, SBEMACS_PYTHON_ORACLE=str(path),
                           SBEMACS_MODE_STALE_INSTALL=str(install_fixture) + "/",
                           SBEMACS_MODE_OLD_INSTALL=str(old_fixture) + "/")
        completed = subprocess.run(command, cwd=ROOT, env=environment, text=True, capture_output=True)
        print(completed.stdout, end="")
        if completed.stderr:
            print(completed.stderr, end="")
        return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
