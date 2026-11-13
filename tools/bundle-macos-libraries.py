"""Copy Homebrew libraries into the app and rewrite their Mach-O references."""
from collections import deque
from pathlib import Path
import shutil
import subprocess
import sys


def bundle(app):
    executables = app / "Contents" / "MacOS"
    libraries = app / "Contents" / "Frameworks"
    libraries.mkdir()
    pending = deque(executables / name for name in ("chezweb-gui", "irene-dixe"))
    copied = {}
    while pending:
        binary = pending.popleft()
        output = subprocess.check_output(["otool", "-L", binary], text=True)
        for line in output.splitlines()[1:]:
            dependency = line.strip().split(" (compatibility version", 1)[0]
            if not dependency.startswith(("/opt/homebrew/", "/usr/local/")):
                continue
            source = Path(dependency).resolve(strict=True)
            target = libraries / Path(dependency).name
            if target in copied and copied[target] != source:
                raise ValueError(f"Conflicting libraries named {target.name}")
            if target not in copied:
                shutil.copyfile(source, target)
                target.chmod(0o755)
                subprocess.run(
                    ["install_name_tool", "-id", f"@rpath/{target.name}", target],
                    check=True,
                )
                copied[target] = source
                pending.append(target)
            prefix = "@loader_path" if binary.parent == libraries else "@loader_path/../Frameworks"
            subprocess.run(
                ["install_name_tool", "-change", dependency, f"{prefix}/{target.name}", binary],
                check=True,
            )


if __name__ == "__main__":
    bundle(Path(sys.argv[1]))
