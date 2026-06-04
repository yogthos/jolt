# Jolt

A Clojure interpreter running on [Janet](https://janet-lang.org). Jolt reads Clojure source text, evaluates it using an interpreter written in pure Janet, and exposes a Clojure-compatible standard library. The goal is a Janet-hosted [SCI](https://github.com/borkdude/sci) runtime — minimal bootstrapping, with SCI as the standard library.

## What's inside

Jolt implements the core of Clojure in a single-process Janet project:

**Reader** — A recursive descent parser for Clojure syntax: symbols, keywords, numbers, strings, characters, lists, vectors, maps, sets, quote forms, reader macros (`#()`, `#_`, `#?`), metadata, deref, and tagged literals.

**Evaluator** — A tree-walking interpreter with 22 special forms (`quote`, `do`, `if`, `def`, `defmacro`, `fn*`, `let*`, `loop*`/`recur`, `throw`, `try`, `set!`, `var`, `locking`, `instance?`, `defmulti`, `defmethod`, `deftype`, `new`, `.`, etc.), syntax-quote with unquote and unquote-splicing, a macro system with `&env` support, destructuring (`:keys` and sequential), and namespace forms (`ns`, `require`, `in-ns`).

**Core library** — 145+ bindings from `clojure.core`: predicates, math with Clojure arity semantics, comparison, collections, sequences, higher-order functions, string functions, I/O, atoms, macros (`when`, `when-not`, `if-let`, `when-let`, `if-some`, `when-some`, `doto`, `fn`, `let`, `defn`, `defrecord`, `defprotocol`), and SCI bootstrap stubs.

**SCI bootstrap** — All 317 forms from SCI's 9 core source files (`macros`, `protocols`, `types`, `unrestrict`, `vars`, `lang`, `utils`, `namespaces`, `core`) load with zero failures. 46 namespaces are populated with 900+ bindings. SCI's `eval-string` is replaced with a Jolt-native implementation.

## Quick start

```bash
git clone https://github.com/yogthos/jolt.git
cd jolt
git submodule update --init   # pulls vendor/sci
jpm build                      # compiles build/jolt
build/jolt                     # drops into REPL
```

## Build

```
jpm build
```

This compiles `src/jolt/*.janet` into a standalone `build/jolt` executable. Requires Janet ≥ 1.36 and `jpm`.

## Run

```
build/jolt
```

Drops into a read-eval-print loop where you can type Clojure expressions:

```
user=> (+ 1 2)
3
user=> (map inc [1 2 3])
[2 3 4]
user=> (defn fib [n] (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
#'user/fib
user=> (fib 10)
55
```

## Test

```
jpm test
```

Runs all tests: API, bootstrap, core, evaluator, macro, namespace, reader, types, and SCI load.

## Use as a library

```janet
(use jolt/api)

(def ctx (init))
(eval-string ctx "(+ 1 2)")       ;; → 3
(eval-string ctx "(map inc [1 2 3])") ;; → [2 3 4]
(eval-string ctx "(def x 42)")    ;; → #'user/x
(eval-string ctx "x")             ;; → 42
```

`(init)` returns a context with `clojure.core` loaded. Pass it to `eval-string` to evaluate Clojure source. Each context is isolated — use separate contexts for separate evaluation environments.

## Janet-native interop

Jolt provides CLJS-style host interop through the `.` special form on any Janet table or struct:

```clojure
;; Field access on tables and structs
user=> (def t {:a 1 :b 2})
user=> (. t :a)          ;; → 1
user=> (.-a t)           ;; → 1 (reader sugar)

;; Method calls — self is passed as first arg
user=> (def obj {:greet (fn [self name] (str "Hello " name))})
user=> (. obj greet "Alice")  ;; → "Hello Alice"

;; Multi-arg methods
user=> (def calc {:add (fn [_ a b] (+ a b))})
user=> (. calc add 3 4)       ;; → 7
```

Any table or struct field that holds a Janet function or C function can be called via `.` with implicit `self` dispatch. This pattern mirrors CLJS `.method` call semantics and unifies deftype protocol dispatch with plain Janet host interop.

**Janet host functions** — Janet's standard library (`os/shell`, `net/request`, etc.) is accessible through Jolt's `jolt.interop` namespace:

```clojure
user=> (require '[jolt.interop :as j])
user=> (j/janet-eval "(+ 1 2)")            ;; → 3
user=> (j/janet-table-keys {:a 1 :b 2})    ;; → [:a :b]
user=> (j/janet-describe "hello")           ;; → Janet type info
```

The existing `jolt.shell`, `jolt.http`, and `jolt.interop` modules demonstrate the pattern: Clojure functions call Janet C functions through the Jolt bridge.

## Project structure

```
src/jolt/
  types.janet       — Var, Namespace, Context, symbol helpers
  reader.janet      — recursive descent parser for Clojure syntax
  evaluator.janet   — tree-walking interpreter
  core.janet        — 145+ clojure.core bindings
  api.janet         — public API: init, eval-string, eval-string*
  main.janet        — REPL entry point
test/                — 8 test suites + SCI load test
vendor/sci/          — SCI submodule (git submodule)
```

## License

[Eclipse Public License 1.0](https://opensource.org/licenses/EPL-1.0)
