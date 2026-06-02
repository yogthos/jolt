---
name: jpm-build
description: Build and debug Janet projects using jpm. Covers project.janet structure, common build errors, and native compilation with create-executable.
---

# JPM Build & Debug

## Build Commands

```bash
jpm build       # Compile and link executable → build/jolt
jpm test        # Run all tests
jpm deps        # Show dependencies
```

## project.janet Structure

```janet
(declare-project
  :name "jolt"
  :description "...")

(declare-source
  :source @["src"])          # Source directories

(declare-executable
  :name "jolt"               # Output binary name
  :entry "src/jolt/main.janet")  # RELATIVE TO PROJECT ROOT, not source dirs
```

## Common Pitfalls

### Entry path is relative to project root
Even though `declare-source` lists `@["src"]`, the `:entry` in `declare-executable` must include `src/` prefix. jpm's `create-executable` calls `dofile source` with the raw entry string.

### main function required for native compilation
`create-executable` extracts a `main` function from the entry file's environment. Top-level code runs during `dofile` and interferes with image generation. Error: "expected integer key for keyword in range [0, 5), got nil".

**Fix:** Wrap startup code in `(defn main [&] ...)`.

```janet
(defn main [&]
  (print "REPL started")
  ;; ... REPL loop ...
)
```

### LSP false positives
Clojure LSP misidentifies `.janet` files. Ignore all diagnostics — they don't affect build or test results.

## Debugging Build Failures

1. Check entry path includes `src/` prefix
2. Check entry file has `(defn main [&] ...)` wrapping top-level code
3. Run `jpm test` to verify code works before native compilation
4. `jpm build` produces no output on success — check exit code only