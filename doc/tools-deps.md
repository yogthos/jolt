# Loading Clojure libraries via deps.edn

Research notes on letting Jolt consume `deps.edn` so a project can pull real
Clojure libraries and `(require ...)` them. This documents what works today, what
it would take, and a recommended path. Nothing here is implemented yet.

## Goal

Given a `deps.edn` like

```clojure
{:paths ["src"]
 :deps  {medley/medley {:mvn/version "1.0.0"}
         some/gitlib    {:git/url "https://..." :git/sha "..."}}}
```

run `jolt` in that directory and have `(require '[medley.core :as m])` find and
load the library's source from the resolved dependency, the same way the stdlib
is loaded today.

## What works today

- **Jolt reads EDN.** `(read-string (slurp "deps.edn"))` parses a deps.edn into a
  Jolt map — no extra parser needed.
- **Library source ships in the jars.** Maven Clojure jars contain the `.clj` /
  `.cljc` source at namespace-matching paths (e.g. `medley/core.cljc`,
  `msgpack/core.clj`), not just compiled `.class` files. So we never need a JVM
  to *run* the code — only to fetch/resolve it, and even that is optional (below).
- **Jolt can run real library source.** Loading `medley/core.cljc` straight from
  its jar works: `(medley.core/abs -5)` → `5`, `(medley.core/find-first odd? …)`
  → `5`. Some functions hit features Jolt doesn't fully support yet — coverage is
  per-function, not all-or-nothing.
- **The real resolver is on the box.** `clojure`, `clj`, and `mvn` are installed,
  with `~/.m2` and `~/.gitlibs` populated. `clojure -Spath` already prints the
  fully-resolved, transitive classpath (dirs + jars).

## What's missing

The loader is single-rooted. `evaluator.janet/ns->path` hardcodes:

```janet
(string "src/jolt/" (dots->slashes (dashes->underscores ns)) ".clj")
```

and `maybe-require-ns` loads exactly that one path if it exists. To load deps we
need:

1. **A classpath** — a list of source roots searched in order, not one fixed
   prefix. Roots = `:paths` from deps.edn + each resolved dependency's source.
2. **`.cljc` support** — try `foo/bar.cljc` as well as `foo/bar.clj` (most libs
   ship `.cljc` or `.clj`; the loader only tries `.clj` today).
3. **`ns`-form handling on load.** Stdlib files have no `ns` form, so
   `maybe-require-ns` sets the current ns manually before loading. Library files
   *do* have `(ns ...)`. Both already work in practice (the `ns` form re-asserts
   the namespace), but the loader should not assume "no ns form."

## Resolving dependencies — three options

The hard part is turning coordinates into local source roots. Maven resolution
(transitive deps, version conflict resolution, POM parsing) is real work; git
deps are comparatively easy.

### A. Shell out to the Clojure CLI (recommended first cut)

Run `clojure -Spath` (optionally `-Sdeps`/aliases) in the project dir, capture
the `:`-separated classpath, then:

- directory entries → add directly as source roots;
- jar entries → extract `*.clj` / `*.cljc` into a cache dir
  (`.jolt/classpath/<sha>/`) with `unzip`/`jar` (both present; Janet has no
  built-in zip) and add the cache dir as a root.

Pros: reuses the canonical resolver, so transitive deps, exclusions, aliases, and
version conflict resolution are all correct and match what JVM Clojure sees. Tiny
amount of code.

Cons: requires the Clojure CLI (hence a JVM) *at resolve time*. Runtime stays
JVM-free. We'd cache the result so resolution only reruns when `deps.edn`
changes.

### B. Jolt-native resolver

Parse `deps.edn` ourselves and resolve:

- `:git/url` + `:git/sha` → `git clone`/checkout into a cache (this is roughly
  what jpm already does for Janet git deps — see "jpm" below);
- `:mvn/version` → download the POM + jar from Maven Central over HTTP, parse the
  POM for transitive deps, resolve versions.

Pros: no JVM dependency at all; self-contained.

Cons: reimplementing Maven resolution (POM transitive graph, `:exclusions`,
nearest-wins version selection) is the bulk of tools.deps and easy to get subtly
wrong. Large effort.

### C. Hybrid

Native path for `:paths` and `:git/*` deps (cheap, no JVM); shell to `clojure
-Spath` only when `:mvn/*` deps are present. Gives a JVM-free experience for
git-only / local projects and correct Maven resolution when needed.

## Where jpm fits

jpm builds the Jolt binary and manages *Janet* packages; it has no Maven/Clojure
notion, so deps.edn support sits beside jpm rather than inside it. Two useful
touch points:

- jpm already fetches and caches **git** repositories for Janet deps — the same
  machinery (or `~/.gitlibs`) can back option B/C's git-dep handling, so we don't
  write a git cache from scratch.
- A project-level `jpm` rule (in `project.janet`) could run resolution as a build
  step and write a classpath file, for projects that want deps resolved at build
  time rather than first run.

But the primary integration is at the Jolt runtime/CLI, not jpm: see below.

## Proposed shape

- **Classpath in the context.** Add a `:classpath` (ordered list of roots) to the
  ctx env. `ns->path` becomes "search each root for `foo/bar.clj` then
  `foo/bar.cljc`", with `src/jolt/` always first so the stdlib wins.
- **Resolution step.** On startup (or via `jolt deps`), if `deps.edn` exists,
  resolve it to roots (option A to start) and set `:classpath`. Cache keyed on a
  hash of `deps.edn` so it's a no-op when unchanged.
- **Config knobs.** `JOLT_CLASSPATH` env / `--classpath` flag to set roots
  directly (bypassing resolution), mirroring how `JOLT_MUTABLE` works.

## Limitations (set expectations)

- **JVM-only libraries don't run.** Anything depending on Java interop, host
  classes, or `clojure.core` features Jolt lacks will fail to load or fail at a
  call. Target audience is pure-`clj`/`cljc` libraries.
- **Coverage is per-function.** As the medley probe showed, a namespace can load
  and have most functions work while a few hit unimplemented core behavior.
- **No AOT/`.class` execution** — ever. We only consume source from the
  classpath; compiled classes in jars are ignored.
- Macro/protocol/reader-conditional support is whatever the Jolt interpreter
  already provides (reader conditionals `#?` are supported, which is why `.cljc`
  loads).

## Recommended plan (phased)

1. **Loader classpath.** Generalize `ns->path`/`maybe-require-ns` to search an
   ordered root list and try `.clj` + `.cljc`. Add `JOLT_CLASSPATH`/`--classpath`.
   No resolution yet — point it at a directory of source by hand and load a lib.
   (Unblocks everything; independently testable.)
2. **deps.edn → classpath via `clojure -Spath` (option A).** Resolve, extract
   jar source to a cache, set the classpath. `jolt deps` to resolve/print;
   auto-resolve on startup when `deps.edn` is present.
3. **Native git deps (toward option C).** Resolve `:git/*` (and `:local/root`)
   without the JVM, falling back to the CLI only for `:mvn/*`.
4. **Conformance pass.** Pull a handful of popular pure-`cljc` libs, see what
   loads/runs, and use the failures to drive interpreter gaps — same loop as the
   clojure-test-suite battery.
