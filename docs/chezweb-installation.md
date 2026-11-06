# Installation

A text editor, like Emacs or Chezweb, has three components:

1. A frontend that inserts characters into a buffer. A buffer is a
   memory region with an image of a text file. One can see the buffer
   as a representation of a scratch pad. As such, the frontend
   provides tools to insert keystrokes at the point indicated by a
   movable cursor.

2. Editing operations that save buffers as files, delete and insert
   text, move the cursor, copy items from one place to another, etc.

3. A scripting language for customizing the Editor.

There is a wide choice of frontends. Some frontends work with a raster
graphics image, which is a dot matrix data structure that represents a
grid of pixels. There are also frontends that are specialized in
showing letters and other characters via an appropriate display
medium. The latter sort of frontend is called Text-based User
Interfaces (TUI), while the former is called Graphical User Interface,
or GUI.

Text-based User Interfaces (TUI) are more comfortable on the eyes,
since they provide sharper and crisper alphabetical letters. On the
other hand, GUI allows for font customization. Schememax, the sister
project of Chezweb, offers both. In a text terminal, it uses
ncurses, which is a text-based user interface. In a window of its own,
it uses SDL2, a library that draws on a grid of pixels, and SDL2\_ttf,
which renders TrueType fonts. The two frontends are compiled into two
separate libraries, so a person who only works in the text terminal
never needs SDL2.

Chezweb itself runs in a browser to facilitate interaction of web
applications, such as Grammarly and NAIA, a medical AI. To activate
the browser interface, press C-c d.

The scripting language is a fast implementation of Scheme inspired
on Dybvig's Chez Scheme.

This chapter installs Chezweb and its dependencies. If you need help,
ask a computer expert or an AI assistant such as Codex or Claude CLI.
If you have never used a terminal, read [Shell](chezweb-shell.md#shell) first.

## Windows: the setup program

Download [Chezweb for Windows (64-bit Intel/AMD)](https://github.com/FemtoEmacs/Femto-Emacs/releases/download/chezweb-windows-0.1/Chezweb-Windows-x86_64-Setup.exe),
run it, and follow the installer. No administrator rights, compiler,
separate Cygwin, WSL or Node.js installation is needed. This is a preview;
its version may lag behind this manual. The [release page](https://github.com/FemtoEmacs/Femto-Emacs/releases/tag/chezweb-windows-0.1)
contains checksums, matching source and test results.

The installer is unsigned. If Windows shows a SmartScreen warning,
verify the download against the release's `SHA256SUMS`; to proceed,
choose *More info*, then *Run anyway*, if offered.

Chezweb installs in `%LOCALAPPDATA%\Programs\Chezweb`, with **Chezweb**
(terminal), **Chezweb GUI** and **Uninstall** Start-menu shortcuts.
Install Google Chrome separately; **C-c d** opens the browser editor
from either native interface. With no filename, Chezweb starts in your
home folder. Settings and personal scripts belong in
`%USERPROFILE%\.chezemax`. Close Chezweb before updating or uninstalling;
uninstallation preserves those settings and your documents.

### Building the Windows installer

The separate `windows` branch contains the build recipe. GitHub's
**Windows installer** workflow compiles the C core and Scheme program,
bundles Cygwin/mintty, ncurses, Wasmtime, SDL and the browser files,
and packages them with NSIS. It tests installation, editing, Scheme,
subprocesses, browser launch and uninstallation, then uploads the
installer, checksums and corresponding source. The browser-launch test
uses a stand-in command.

Maintainers on Linux or macOS can select **Actions → Windows installer → Run workflow**
on that branch to build on GitHub's Windows runner. For a local Windows
build, install NSIS and Cygwin with `git`, `gcc-core`, `binutils`, `make`,
`libncurses-devel`, `pkg-config`, `curl`, `unzip`, `xz` and `mintty`.
In the Cygwin shell:

```sh
git clone --branch windows https://github.com/FemtoEmacs/Femto-Emacs.git chezmoi-windows
cd chezmoi-windows
bash windows/build-installer.sh
```

The installer is `build/windows/Chezweb-Windows-x86_64-Setup.exe`.
The [workflow](https://github.com/FemtoEmacs/Femto-Emacs/blob/windows/.github/workflows/build-windows-installer.yml)
is the complete build-and-test recipe.

## Cloning the GitHub repository

Git copies Chezweb's source and change history from GitHub. Check for it
with `git --version`. On macOS, install Git, the C compiler and `make`:

```sh
xcode-select --install
```

On Debian or Ubuntu, install the build dependencies:

```sh
sudo apt-get install git build-essential libncurses-dev pkg-config curl xz-utils
```

Clone into `~/mysand/chezmoi`:

```sh
mkdir -p ~/mysand
cd ~/mysand
git clone https://github.com/FemtoEmacs/Femto-Emacs.git chezmoi
cd chezmoi
```

The final argument names the new folder; without it, Git uses
`Femto-Emacs`. To update later, enter that folder and run `git pull`,
then rebuild with `make`.

## ncurses

Chezweb's terminal interface uses ncurses. Source builds need its
library and development headers; Linux uses the wide-character version,
`ncursesw`, for Unicode text such as *café* and *façade*.

### macOS

The system provides ncurses; Xcode's command-line tools provide its
headers. Check them with:

```sh
tic -V
ls "$(xcrun --show-sdk-path)/usr/include/ncurses.h"
```

If the tools are missing, run `xcode-select --install`.

### Linux

Check with `pkg-config --modversion ncursesw`. Install missing headers:

```sh
sudo apt-get install libncurses-dev pkg-config  # Debian/Ubuntu
sudo dnf install ncurses-devel pkgconf-pkg-config  # Fedora
```

### Windows

The preview installer includes ncurses. Developers need Cygwin's
`libncurses-devel`, as described in [Building the Windows installer](#building-the-windows-installer).

## SDL: the optional graphical interface

SDL2 and SDL2_ttf provide Chezweb's own window. The terminal and browser
interfaces do not require them.

### macOS

With Homebrew installed:

```sh
brew install pkg-config sdl2 sdl2_ttf
```

### Linux

On Debian or Ubuntu:

```sh
sudo apt-get install libsdl2-dev libsdl2-ttf-dev
```

### Windows

The preview installer includes SDL; choose **Chezweb GUI**
in the Start menu.

### Try it

After installing the libraries, run `make` in `~/mysand/chezmoi`, then
`./chezweb-gui`. `make show-config` reports whether SDL was found.

## Building Chezweb

In the repository folder, run:

```sh
make
```

The makefile builds the C editor and Scheme compiler, compiles the Scheme
scripts, downloads a checksum-verified Wasmtime runtime, and installs the
bundled browser files. It also builds the GUI when SDL is available.
No separate Scheme installation, Lean, Node.js or browser compiler is
needed. The first build requires internet access and may take several minutes.

Run `make` as your ordinary user: this checkout has no `make install`
target and needs no `sudo`. Keep the executables with their runtime and
support folders. On macOS, `make app` creates `Chezweb.app` for launching
from Finder.

## Running Chezweb

On macOS or Linux, run from the repository folder:

```sh
./chezweb                      # terminal
./chezweb notes.md             # open a file
./chezweb-gui notes.md         # optional GUI
```

With Google Chrome installed, press **C-c d** in either interface to open
the current buffer in the browser. The native window stays open. On Windows, use the Start-menu shortcuts
installed by the setup program.

To run from any folder on macOS or Linux, add this line to `~/.zshrc`
for zsh or `~/.bashrc` for interactive bash (`~/.bash_profile` for a bash
login shell). Adjust the folder if you cloned elsewhere:

```sh
export PATH="$HOME/mysand/chezmoi:$PATH"
```

Open a new terminal, or reload the appropriate file with, for example,
`source ~/.zshrc`. You can then run `chezweb notes.md` or
`chezweb-gui notes.md` from any folder; `command -v chezweb` shows which
copy will run.

