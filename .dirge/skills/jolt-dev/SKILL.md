# jolt-dev

Jolt development workflow — build, test, special form patterns, Janet gotchas

# Jolt Development

## Build & Test

```bash
cd /Users/yogthos/src/jolt
jpm build           # produces build/jolt
jpm test            # runs all tests
janet test/foo.janet  # run a single test file from project root
```

## Special Form Checklist

To add a new special form to the evaluator:

1. Add the name to `special-symbol?` in `src/jolt/evaluator.janet`
2. Add a match arm in `eval-list` (the match on `name`)
3. Add tests in `test/evaluator-test.janet`

The match arm receives `ctx`, `bindings`, and `form` (the full list). Use `(in form 1)` for first arg, etc.

**Non-symbol heads** (keywords, etc.): `eval-list` first checks `(and (struct? first-form) (= :symbol (...)))` before extracting `name`. If not a symbol, falls through to default function application.

### Current special forms (22):
`quote`, `syntax-quote`, `unquote`, `unquote-splicing`, `do`, `if`, `def`, `defmacro`, `fn*`, `let*`, `loop*`, `recur`, `throw`, `try`, `set!`, `var`, `locking`, `instance?`, `defmulti`, `defmethod`, `deftype`, `new`, `.`

## Pers… (truncated, 34945 bytes total)