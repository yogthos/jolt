# Jolt

A Clojure interpreter running on [Janet](https://janet-lang.org). Jolt reads Clojure source text, evaluates it using an interpreter written in pure Janet, and exposes a Clojure-compatible standard library.

## What's inside

Jolt implements the core of Clojure in a single-process, no-dependency Janet project:

**Reader** — A recursive descent parser for Clojure syntax: symbols, keywords, numbers, strings, characters, lists, vectors, maps, sets, quote forms, reader macros (`#()`, `#_`, `#?`), metadata, deref, and tagged literals.

**Evaluator** — A tree-walking interpreter with special forms (`quote`, `do`, `if`, `def`, `fn*`, `let*`, `loop*`/`recur`), syntax-quote with unquote and unquote-splicing, a macro system, and namespace forms (`ns`, `require`, `in-ns`).

**Core library** — 95+ functions from `clojure.core`: predicates, math with Clojure arity semantics, comparison, collection operations (conj, assoc, dissoc, get, merge, keys, vals), sequence operations (map, filter, reduce, take, drop, take-while, drop-while, concat, reverse, sort, distinct, group-by, partition), range and repeat, higher-order functions (comp, complement, constantly, juxt, memoize, partial), collection constructors, string functions, I/O, and atoms.

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

To pre-populate a context with values:

```janet
(use jolt/api)

(def ctx (init {:namespaces {"user" {"greeting" "hello"}}}))
(eval-string ctx "(str greeting \" world\")") ;; → "hello world"
```

## License

[Eclipse Public License 1.0](https://opensource.org/licenses/EPL-1.0)
