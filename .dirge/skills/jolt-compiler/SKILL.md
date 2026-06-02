---
description: Jolt compiler architecture and implementation plan
---

# Jolt Compiler

Two-phase source-to-source compiler: Clojure forms → annotated AST → Janet source → Janet bytecode.

## Architecture

```
Clojure source → Reader → raw AST
                            ↓
                   analyze-form (classify symbols, produce :op AST)
                            ↓
                   emit* dispatch (generate Janet source string)
                            ↓
                   Janet compile → bytecode
```

Follows CLJS `cljs.analyzer` / `cljs.compiler` pattern.

## Key decisions

- **Target**: Janet source text (fed to Janet's `compile`), not direct bytecode. Simpler, debuggable, portable across Janet versions.
- **Mode gating**: Opt-in per context via `:compile?` flag on `init`. `eval-string` still interprets unless opted in.
- **Caching**: In-memory bytecode cache in context first. Disk persistence (`.jimage` files) as follow-up.

## AST ops (CLJS subset + Jolt-specific)

Core: `const`, `var`, `local`, `binding`, `if`, `do`, `let`, `loop`, `recur`, `fn`, `fn-method`, `def`, `invoke`, `quote`, `try`, `throw`, `set!`, `new`, `host-field`, `host-call`

Jolt-specific: `deftype`, `defmulti`, `defmethod`, `syntax-quote`

## File layout

| File | Purpose |
|------|---------|
| `src/jolt/compiler.janet` | `analyze-form`, `emit*` dispatch, `compile-form`, symbol classifier |
| `src/jolt/loader.janet` | `load-ns`, `reload-ns`, in-memory bytecode cache |
| `test/compiler-test.janet` | Round-trip: compile-form → Janet eval → assert |

Modified files:
- `evaluator.janet` — add compiler fast-path for `def`/`defn`/`defmacro` when `:compile?` set
- `types.janet` — add `:compiled-cache` table to context
- `api.janet` — expose `compile-string`, `load-ns`, `compile-file`; `init` gets `:compile?` flag
- `reader.janet` — **no change**
- `core.janet` — **no change**

## Emit target advantages

Both input and output are parenthesized prefix syntax, so many forms pass through almost unchanged:

```
Clojure:  (defn f [x] (+ x 1))
AST:      {:op :def :name "f" :init {:op :fn :methods [...]}}
Janet:    (defn f [x] (+ x 1))          ← nearly identical
```

Main work:
- Symbol resolution (Clojure's `clojure.core/+` → Janet's `core-+`)
- Truthiness wrapping (`nil`/`false` are falsey in Clojure, Janet only `nil`)
- Special form mapping (`loop*`/`recur` → Janet `loop` + explicit recur vars)
- Vars → Janet table lookups

## Implementation phases

| Phase | What | Deliverable |
|-------|------|-------------|
| 1 | `compiler.janet` — `analyze-form` skeleton + `emit*` for `const`, `do`, `if`, `let`, `fn`, `def`, `invoke` | Basic forms compile and run |
| 2 | Symbol classifier — resolve locals/vars/core at analyze time | No runtime `resolve-sym` in compiled code |
| 3 | `loader.janet` + `api.janet` wiring — `:compile?` flag, `load-ns`, caching | File-based namespace loading works |
| 4 | Macro integration — expand at analyze time via interpreter | Macros work in compiled code |
| 5 | Remaining ops: `loop`/`recur`, `try`/`throw`, `quote`, `syntax-quote`, `set!`, `deftype`, `.` | Full language coverage |
| 6 | Tests + benchmarks | Correctness + speedup measurement |

## Pitfalls

- Janet `compile` produces bytecode tied to Janet version — source-to-source avoids this
- CLJS analyzer is ~5000 lines; Jolt's can be simpler because emit target is s-expressions
- Symbol resolution must happen at analyze time, not runtime, for compiled code
- Macro expansion still uses interpreter at analyze time — macros are not AOT-compiled
