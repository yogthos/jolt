# Building and dependencies

How to build Jolt from source and how to pull Clojure libraries into a project.

## Building

```bash
git clone https://github.com/jolt-lang/jolt.git
cd jolt
git submodule update --init   # vendor/sci (used by the SCI bootstrap tests)
jpm build
```

This produces two executables under `build/`:

- **`jolt`** — the runtime: REPL, file/expr runner, nREPL server. The whole `.clj`
  standard library (`clojure.string`/`set`/`walk`/`edn`/`zip`, `jolt.http`/
  `interop`/`shell`/`nrepl`) is baked into this binary at build time, so it loads
  from any directory — the build artifact is self-contained. (`clojure.core` is
  built into the runtime in Janet and auto-referred, so it's always available.)
- **`jolt-deps`** — a separate tool that resolves a `deps.edn` (see below). It
  sits beside the runtime the way `jpm` sits beside `janet`; the runtime itself
  knows nothing about deps.edn.

Needs `jpm` and a recent Janet — developed and CI-tested against **1.41**. The
futures and core.async layers use Janet's threaded `ev/` channels (`ev/thread`,
`ev/thread-chan`), so older Janets may not run the full suite.

`jpm build` doesn't always notice source changes; run `jpm clean && jpm build`
after editing `src/` to be sure the binaries are current. `jpm test` runs against
the source directly, so it never goes stale.

## How namespaces are found

`(require ...)` resolves a namespace to a file by searching an ordered list of
source roots — the stdlib first, then any extra roots — trying `<ns>.clj` then
`<ns>.cljc` (dots become directories, dashes become underscores). Extra roots
come from:

- `JOLT_PATH` — a colon-separated list of directories (like a classpath), applied
  at runtime;
- the `:paths` option to `init` when embedding Jolt as a library.

If a namespace isn't found on any root, the loader falls back to the stdlib baked
into the binary — that's how `clojure.string` and friends resolve when you run
the binary outside the source tree.

So you can point Jolt at a directory of Clojure source with no deps machinery at
all:

```bash
JOLT_PATH=/path/to/lib/src build/jolt myfile.clj
```

## Dependencies via deps.edn

`jolt-deps` reads a `deps.edn` in the current directory, fetches its
dependencies, and runs `jolt` with the resolved source directories on
`JOLT_PATH`.

```bash
jolt-deps path             # print the resolved roots (':'-joined)
jolt-deps run FILE [args]  # resolve, then run `jolt FILE …`
jolt-deps repl             # resolve, then start a REPL
jolt-deps -e EXPR [args]   # resolve, then evaluate EXPR
jolt-deps -A:dev path      # include the :dev alias's extra paths/deps
jolt-deps -M:test [args]   # run the :test alias's :main-opts through jolt
jolt-deps tasks            # list :tasks from deps.edn
jolt-deps task NAME [args] # run a task
```

`jolt-deps` launches the `jolt` binary it finds on `PATH` (override with
`$JOLT_BIN`).

Example `deps.edn`:

```clojure
{:paths ["src"]
 :deps {weavejester/medley {:git/url "https://github.com/weavejester/medley"
                            :git/tag "1.0.0"}
        my/helpers          {:local/root "../helpers"}}}
```

```bash
jolt-deps run -m myapp.main
```

### What's supported

- **git deps** — `{:git/url … :git/tag …}` or `{:git/url … :git/sha …}` (use a
  full SHA; `git fetch` can't resolve a short one). Transitive deps from each
  dependency's own `deps.edn` are resolved too.
- **local deps** — `{:local/root "../path"}`.
- The project's own `:paths` (default `["src"]`) are included.
- **aliases** — `:aliases {:dev {:extra-paths ["dev"] :extra-deps {…}
  :main-opts ["-e" "…"]}}`, selected with `-A:dev` (or several: `-A:dev:test`).
  `:extra-paths`/`:extra-deps` accumulate across selected aliases;
  `:main-opts` is last-wins and runs via `-M:alias`.
- **user config** — a `deps.edn` under `$JOLT_CONFIG` (else
  `$XDG_CONFIG_HOME/jolt`, else `~/.jolt`) merges beneath the project's, the
  way `~/.clojure/deps.edn` does: `:deps`/`:aliases`/`:tasks` merge per key
  with the project winning.
- **tasks** — `:tasks {clean "rm -rf target" test {:doc "run the suite"
  :main-opts ["-e" "(run-tests)"]}}`. A string task is a shell command; a map
  task runs jolt with its `:main-opts`. `jolt-deps tasks` lists, `jolt-deps
  task NAME` runs.

Conflicts resolve the tools.deps way: resolution is breadth-first, so a
top-level coordinate always beats a transitive one for the same lib, and
conflicting coordinates print a warning naming both.

Git clones land in a global, sha-immutable cache shared across projects —
`$JOLT_GITLIBS`, else `<config-dir>/gitlibs` (the `~/.gitlibs` model). The
resolved roots are cached per project in `.cpcache/jolt-deps.jdn`, keyed on a
hash of the project `deps.edn` + the user `deps.edn` + the selected aliases.

### What's not

- **No Maven.** `:mvn/version` deps are ignored — git and local only.
- **Pure `clj`/`cljc` only.** A library that needs the JVM (Java interop, host
  classes) or a `clojure.core` feature Jolt doesn't implement will fail to load
  or fail at a call. Coverage is per-function: a namespace can load with most
  functions working and a few not.

### Bundling into one file

`jolt uberscript OUT.clj -m NS` (or `jolt-deps uberscript …`, which resolves deps
first) bundles `NS` and every namespace it requires — your code plus its
dependencies — into a single `.clj` in dependency order, ending with a call to
`NS/-main`. The result runs on a plain `jolt` with no `JOLT_PATH`, no deps
fetched, and no jpm:

```bash
jolt-deps uberscript app.clj -m myapp.main
jolt app.clj arg1 arg2
```

See [`tools-deps.md`](tools-deps.md) for the design rationale.
