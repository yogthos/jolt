Janet break can't be used inside let blocks — break returns from the innermost loop, and in a let, there's no loop. Pattern: use (var found nil) + (while ... (if condition (do (set found val) (break)))) then check found after loop.
§
core-binding macro: use array-map (plain struct) NOT hash-map/PHM for the binding frame. PHM's phm-get doesn't work with push-thread-bindings' var-get lookup. Symptom: "error: dynamic binding" with no useful message. Fix: emit (array-map [var sym] val ...) instead of (hash-map ...).
§
Janet `and` returns the last truthy value (not boolean true). `(and (table? x) (get x :jolt/deftype))` returns the deftype string, which is truthy but not `true`. Wrap with `(if (and ...) true false)` when the return value must be a boolean. This hit core-map? and would hit any predicate returning the result of `and`.
§
set! field mutation: `(set! (.-x obj) val)` is read as `(set! (. -x obj) val)` — the target is an array with `.` as head. Check for this case BEFORE the existing `(.-field obj)` shorthand check (which is just `(. obj -field)`). The reader transforms `.`-prefixed symbols differently than expected: `.-x` becomes a symbol `-x` inside a `(. -x obj)` array form, NOT a standalone `.-x` symbol.
