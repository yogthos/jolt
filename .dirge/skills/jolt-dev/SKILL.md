# jolt-dev

Jolt development workflow — build, test, special form patterns, Janet gotchas

## Build & Test

```bash
cd /Users/yogthos/src/jolt
jpm build           # produces build/jolt (gitignored)
jpm test            # runs all tests (test-load-sci times out occasionally)
janet test/foo.janet  # run a single test file from project root
```

Build artifacts are in `build/` which is `.gitignore`d.

## Architecture

Jolt is a **Janet-hosted SCI** — Jolt's reader + evaluator form the runtime, SCI provides the standard library. Load order: macros → protocols → types → unrestrict → vars → lang → utils → namespaces → core (all 317 forms, 0 failures). Source: `vendor/sci/src/sci/` (git submodule).

`sci.core/eval-string` is replaced with Jolt-native: `(eval-form ctx @{} @[{:jolt/type :symbol :ns nil :name "do"} (parse-string s)])`. This bypasses SCI's interpreter/parser/analyzer pipeline. SCI internal namespaces (interpreter, parser, analyzer, opts) have 0 bindings after loading — they require loading their own source files.

## SCI Submodule

SCI is at `vendor/sci` (git submodule, github.com/borkdude/sci). Load order: macros → protocols → types → unrestrict → vars → lang → utils → namespaces → core

## Project Structure

```
src/jolt/
  types.janet      — Var, Namespace, Context, symbol helpers
  reader.janet     — recursive descent parser for Clojure syntax
  evaluator.janet  — tree-walking interpreter (eval-form, eval-list, syntax-quote*)
  core.janet       — clojure.core bindings: predicates, math, collections, macros, stubs
  api.janet        — public API: init, eval-string, eval-string*
  main.janet       — REPL entry point

test/
  evaluator-test.janet  — special form tests
  reader-test.janet     — parser tests
  core-test.janet       — core library tests
  macro-test.janet      — syntax-quote and macro tests
  namespace-test.janet  — ns, require, in-ns tests
  types-test.janet      — Var and Namespace tests
  api-test.janet        — public API tests
  bootstrap-test.janet  — loads sci.impl.macros
  test-load-sci.janet   — loads all sci files + tests eval-string
```

## Janet Gotchas

- **`try` form**: `(try body ([err] handler))` — the `([err] handler)` must be ONE line. Multi-line break after `([err]` causes "unexpected closing delimiter )" parse error. Correct: `(try (do-stuff) ([err] nil))`.
- **`try` separate from `([err]`**: `(try body-form ([err] handler))` is valid — `body-form` and `([err]` on same line.
- **`(string :kw)`** converts keyword to string. Janet has no `name` function.
- **`(put {:x 1} :y 2)`** errors — structs don't support `put`. Use `@{}` tables for mutable maps.
- **`(put table key nil)`** silently drops the key. Use `bind-put` + `:jolt/nil-sentinel` pattern.
- **`var`** declares mutable locals; `def`/`let` are immutable.
- **`(set [a b] tuple)`** doesn't work — use explicit indexing `(tuple 0)` / `(tuple 1)`.
- **`(last "string")`** returns nil — works only on indexed types.
- **Multi-arity `defn` in Janet**: Use `(fn [& args] (case (length args) ...))` pattern. `defn-?` doesn't exist.
- **`indexed?` vs `array?`**: Reader produces tuples for vectors, arrays for lists. Check `indexed?` for vector patterns.
- **`match`** returns nil on no match — used in `eval-list` for non-symbol head fallthrough.
- **`(length struct)`** counts pairs, not keys. Use `(length (keys struct))`.
- **`(first struct)`** calls `:jolt/type` method — use `(get struct :key)`.

## Special Form Checklist

To add a new special form:
1. Add the name to `special-symbol?` in `src/jolt/evaluator.janet`
2. Add a match arm in `eval-list`
3. Add tests in `test/evaluator-test.janet`

Current: `quote`, `syntax-quote`, `unquote`, `unquote-splicing`, `do`, `if`, `def`, `defmacro`, `fn*`, `let*`, `loop*`, `recur`, `throw`, `try`, `set!`, `var`, `locking`, `instance?`, `defmulti`, `defmethod`, `deftype`, `new`, `.`

## Core Macros and Functions

### gensym
```janet
(def gensym_counter @{:val 0})
(defn gensym [&opt prefix-string]
  (default prefix-string "G__")
  (def n (get gensym_counter :val))
  (put gensym_counter :val (+ n 1))
  {:jolt/type :symbol :ns nil :name (string prefix-string n)})
```

### core-name
Returns name string of keyword, symbol, or string. Uses `(string kw)` for keywords, `.name` field for symbols.

### Registered macros in core-macro-names
`when`, `when-not`, `if-let`, `when-let`, `if-some`, `when-some`, `doto`, `defn`, `defn-`, `declare`, `fn`, `let`, `defrecord`, `defprotocol`, `extend-type`, `extend-protocol`, `extend`, `reify`, `proxy`, `definterface`, `comment`

### defrecord stub
Generates `->TypeName` positional constructor. Expands to `(do (def TypeName (fn* [fields] ...)) (def ->TypeName ...))`.

### doto macro
Uses `gensym` for the object symbol. Expands to `(let* [sym obj] (. sym method args)... sym)`.

### defmacro details
- Supports optional docstring: `(defmacro name [args] body)` or `(defmacro name "doc" [args] body)`
- Implicit `&env` binding: `(put new-bindings "&env" @{})` — table, not struct (nil-safe)
- Capture defining namespace for symbol resolution in macro bodies

## Janet Table Nil-Drop Workaround

`(put table key nil)` silently drops the key. Workflow:
1. `bind-put` helper in `evaluator.janet` stores nil as `:jolt/nil` sentinel
2. `resolve-sym` unwraps `:jolt/nil` back to `nil`
3. Dynamic vars with nil values (`*1`, `*2`, `*3`, `*e`) use `:jolt/nil-sentinel` in `core-bindings`
4. `init-core!` checks for `:jolt/nil-sentinel` and passes actual nil to `ns-intern`