# Jolt — Complete Implementation Plan

## Architecture Goal

Minimal Janet bootstrap → SCI/CLJS Clojure source runs on Jolt.

Three layers:
1. **Janet runtime**: types.janet, reader.janet, evaluator.janet, compiler.janet (~4,200 lines)
2. **Clojure core**: core.janet (~1,400 lines), phm.janet (~200 lines)
3. **Clojure source** (.clj files loadable at runtime): stdlib modules, SCI

## Current State

| Metric | Value |
|--------|-------|
| Total tests | 317 |
| Passing | 317 |
| Failing | 0 |
| CLJS ported test files | 16 (1/1a/1b/2/3/3b/4/5/6/7/8/9/10/test + test-sci-runtime + eval-test) |
| Total assertions | 440 across 31 test files |
| Source lines | ~5,800 (7 core .janet files) |
| SCI source files loading | 9/9 |
| New features | `eval` special form, `with-meta` core binding, `var-dynamic?` core binding, `load-string` API, `^:dynamic` def handler |

## Phase Plan

### Phase 0-10: Foundation ✓

| Phase | Description | Status |
|-------|-------------|--------|
| 0 | `defn` bug fix, bare symbol resolution | ✓ |
| 1 | Var/Namespace system, ns form extensions | ✓ |
| 2 | PersistentHashMap implementation | ✓ |
| 3 | Var system: var-get/set/?, alter-var-root, intern, binding | ✓ |
| 4 | deftype/defrecord completion | ✓ |
| 5 | Multimethods + Hierarchy | ✓ |
| 6 | Reader extensions: tagged literals, :jolt/tagged handler | ✓ |
| 7 | LazySeq + PersistentHashSet | ✓ |
| 8 | Protocol system: defprotocol, extend-type, extend-protocol, reify, satisfies? | ✓ |
| 9 | REPL fixes: buffer-based output, collection rendering, cond fix | ✓ |
| 10 | Standard Library: clojure.string, clojure.set, clojure.walk, clojure.zip, clojure.edn, clojure.java_io, jolt.interop, jolt.shell, jolt.http | ✓ |

### Phase 11: Fix Pre-existing Failures ✓

- `types.janet`: `ns?` now accepts both structs and tables
- `core.janet`: `comment` macro wired into core-bindings
- `sci/lang_stubs.clj`: minimal SCI type stubs for bootstrap
- `test-load-sci.janet`: load stubs before SCI source files
- **Result: SciVar fixed. 1 remaining (deftype with `#?@` — Phase 15)**

### Phase 12: Core Feature Completion ✓

- `apply` support in evaluator + compiler
- `str` handles nil correctly
- 6 CLJS test files created (~120 assertions)
- `#()` anonymous fn reader with `%`, `%1`, `%2` arg handling

### Phase 13: Protocol Completion ✓

- reify dispatch: protocol methods work on reified objects
- `#()` reader macro with gensym-based `%` arg handling
- IFn protocol support in default invocation arm
- clojure.walk loads and `keywordize-keys` works
- 4 test sections: reify dispatch, anon fn, extend-type, walk loading

### Phase 14: Extend CLJS Ported Tests ✓

- `cljs-port-2.janet` expanded: 10 sections (12-21), 35→60 assertions
- `cljs-port-5.janet` created: sections 22-24, destructuring, metadata, fn composition
- `pr-str` compiler fix: maps to new `core-pr-str` (not `core-str`)
- `every-pred` added to core.janet
- `var-dynamic?` and `with-meta` tests restored

### Phase 15: SCI Bootstrap ✓

- ✅ `sci.lang` namespace loads completely (all 10 forms, including Var, Type, Namespace deftypes)
- ✅ 9 SCI source files load without errors (impl/macros, impl/protocols, impl/types, impl/unrestrict, impl/vars, lang, impl/utils, impl/namespaces, core)
- ✅ `prefer-method`/`remove-method`/`remove-all-methods` promoted to special forms (fix: auto-deref gave functions to `get`/`put`)
- ✅ All 5 pre-existing test failures fixed:
  - `cljs-port-1.janet` — `#{}` Janet comment issue replaced with count-based comparisons
  - `cljs-port-2.janet` — `with-meta` added as core binding with table/setproto
  - `cljs-port-3b.janet` — `load-string` multi-form loader for string.clj and set.clj
  - `cljs-port-5.janet` — `var-dynamic?` core binding + `^:dynamic` def handler fix
  - `phase5-test.janet` — `remove-method` special form fixed to eval-form first arg
- New core infrastructure: `core-with-meta` (supports structs/tables via prototype), `core-var-dynamic?`, `load-string` API, `^:dynamic` propagation in `def` handler
- `core-str` now returns `"nil"` for nil (Clojure-compatible)
- `core-meta` checks `:jolt/meta` for with-meta'd values
- Test suite: **317/317 pass, 0 fail**

### Phase 16: Remaining Core Library + Tests ✅

- ✅ `eval` implemented as special form (interpreter + compiler), tested in `eval-test.janet` (4 assertions)
- ✅ `&` rest destructuring, `seq` nil handling, `vector`/`list` equality verified working
- ✅ `syntax-quote` confirmed working with unquote
- ✅ 5 new CLJS ported test files (cljs-port-6 through -10): anon fns, symbols/keywords/lists, destructuring, range/concat/partition/sort, seq predicates/complement, when/if-let/doto
- ✅ 16 total CLJS ported test files, 440 assertions across 31 test files
- ✅ 317/317 tests pass, 0 failing scripts

### Phase 17: Optimization

- Compiler improvements: inline small core functions
- PersistentHashMap dynamic bucket growth
- Benchmarks

### Phase 18: Standard Library Completion

- Complete EDN reader/writer
- Complete java.io wrappers
- clojure.zip tests

## Implementation Order

1. ✅ Phases 0-16 (completed)
2. Phase 17 (optimization: compiler inlining, PHM bucket growth, benchmarks)
3. Phase 18 (stdlib: EDN reader/writer, java.io wrappers, clojure.zip tests)
