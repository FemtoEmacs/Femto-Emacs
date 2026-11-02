> Schememax's notes, kept for their history. For Chezemax, PORT-TO-SCHEMER.md
> replaces this file.

# Runtime migration status

The compiler is now self-hosted WasmGC. Compilation in both products no longer
runs FemtoScheme. Schememax uses a standalone Wasmtime C driver; Browsered
instantiates the embedded compiler module directly. The old bootstrap launcher
and generated second compiler VM have been retired into local backup folders.

The editors are not yet pure compiled Scheme. Remaining active dependencies:

- Editor startup loads femtoscheme.boot and scheme/init.scm.
- C primitives, hooks, highlighting and event dispatch use FemtoScheme values,
  allocation and garbage collection.
- Editor macros and dynamic global definitions run in that environment.
- Compiled editor RPC serializes data through the interpreter; ports, shared
  mutable objects and higher-order callbacks need a typed compiled interface.
- Command and expression compatibility selection still routes unsupported
  constructs into the interpreter before execution.

A complete removal must replace those paths together, compile editor startup
and extensions, and preserve mutable identity, error handling, interactive
prompts and file/process behavior. Merely deleting fallback handlers would
break existing editing commands. Retrying after a compiled failure is unsafe.

Completion criteria: both products start and edit without loading the boot
image or linking the old interpreter, and their keyboard, prompt, buffer,
file-save, shell and mocked assistant regression suites pass in that state.
Existing passing tests still include the old editor runtime and do not prove
this final criterion. The old runtime folder must remain until then.
