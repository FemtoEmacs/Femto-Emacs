# Repository transition to Chezemax

On 2 November 2026, master was populated from the implementation in the
maintainer's claude-sandbox/chezemax source tree. This is a normal commit
following the existing Femto-Emacs master history, not a new GitHub repository.

The legacy branch preserves the original master at
abb1c38668ac2ce08603db17ead729e77ead31b8. Existing stars and the fork network
remain with FemtoEmacs/Femto-Emacs. Fork owners can choose whether to merge
the successor implementation.

The obsolete codemax remote branch is retired by this migration; its last
commit was bab220b3c3c6c9cf0022083ec4d984584ff3e987. Its history is retained
in the migration checkout's local archive/codemax-before-migration branch.
The sbcl and windows branches are outside this master migration. Windows
installer publication is separate work.

Only application sources, documentation, tests and the self-hosted compiler
seed are imported. Private papers, backups, scratch documents, native
binaries, SDKs and machine-code caches are excluded. Build outputs are
produced by make. The original source folder remains separate from this
Git checkout.

## Chezweb replaces master

On 2 November 2026, master was updated from ~/claude-sandbox/chezweb.
This is a normal successor commit after f34ab7b509c8d6521ef87d13a59f98d98d6bb795.
The existing Intel/ARM macOS and Linux build support is retained. Legacy,
sbcl and windows remain separate branches. Chezweb adds a JSPI browser
editor, optional Grammarly checking and Chrome-granted folder access.
The source folder remains separate from this publishing checkout.
