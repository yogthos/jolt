Bare tuples in Janet's `eval` are function calls: `(eval [1 2 3])` tries to call `1` as function. Always emit `['tuple 1 2 3]` or `(tuple 1 2 3)` in data-structure emitter. Similarly, `(eval (try body (sym handler)))` fails because `catch` is not a Janet special form — must be `(try body ([sym] handler))`. Discovered during Phase 5/6 compiler work.
§
Duplicate function definitions in the same file cause hard-to-diagnose "unknown symbol" errors. In compiler.janet, emit-quote-str was defined twice (once before emit-ast dispatch, once before emit-expr section). The second definition compiled but the first was used by emit-ast dispatch — causing "unknown symbol raw-form->janet". Always grep for the fn name before adding a new definition.
§
Janet break can't be used inside let blocks — break returns from the innermost loop, and in a let, there's no loop. Pattern: use (var found nil) + (while ... (if condition (do (set found val) (break)))) then check found after loop.
§
core-binding macro: use array-map (plain struct) NOT hash-map/PHM for the binding frame. PHM's phm-get doesn't work with push-thread-bindings' var-get lookup. Symptom: "error: dynamic binding" with no useful message. Fix: emit (array-map [var sym] val ...) instead of (hash-map ...).
