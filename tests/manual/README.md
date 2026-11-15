# Manual tests

Some behaviour can only be checked by a person at the keyboard: Chrome
and the native window side by side, the mouse, a terminal resized by
hand. These scripts walk a tester through it, step by step, while the
backdoor (see AGENTS.md) records what the editor did. The record and the
test files are then compared with EXPECTED.md, by a maintainer or by the
AI on the tester's machine.

| Script | What it tests |
|---|---|
| `natbrowser-interaction.org` | C-x C-s in either window (browser or native) saves the file and puts its text in the other; unsaved edits go to `#name#`; read-only buffers, C-x k, Save As, an open prompt, a granted folder |
| `vsplit.md` | the side-by-side split (C-x 3): the window kept, typing, Korean, the mouse, M-x term in a pane, resizing |

`pt/` has the scripts in Portuguese, `en/` in English, each with its
disposable test files. `backdoor.conf` is the backdoor's configuration
for both scripts. Step 0 of each script says how to begin: copy the
folder of your language to `~/chezweb-testes` (Portuguese) or
`~/chezweb-tests` (English), copy `backdoor.conf` to
`~/.chezemax/backdoor-claude.conf`, and open the script there; the
tests then change only those copies, never the repository.

## Testes manuais (em português)

Estes roteiros guiam um testador, passo a passo, enquanto o backdoor do
editor registra o que aconteceu. Os roteiros em português estão em
`pt/`; o passo 0 de cada um diz como começar. No fim, envie a pasta
`~/chezweb-testes` para quem pediu o teste, ou peça ao Claude da sua
máquina, aberto na pasta do repositório, que confira o resultado com
`EXPECTED.md`.
