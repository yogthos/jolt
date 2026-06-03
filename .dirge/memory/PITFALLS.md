Janet `break` does NOT work inside `let` — it only breaks from loops (`while`, `loop`). When searching for a key in a bucket and needing to return a value, use `(var found nil)` + `(set found val) (break)` pattern then check `found` after the loop. Same for `break nil` in bucket-dissoc: capture index in a var, break, then construct result after loop.
§
Keywords containing `#` (like `:#inst`, `:#uuid`) are invalid Janet literal syntax. Use dynamic table construction: `(let [dr @{}] (put dr (keyword "#inst") fn) dr)` instead of `@{:#inst fn}`. This hit us in types.janet make-ctx :data-readers initialization.
§
PHM/Set internal metadata keys (`:jolt/deftype`, `:cnt`, `:buckets`, `:_meta`, `:jolt/type`, `:phm`) leak into `pairs`/`keys` iteration. Must filter them in core fns like merge, merge-with, keys, vals, and in print-rendering code. `core-merge` without filtering produced corrupted PHMs with metadata as entries. Commit `9c44021` fixed this for merge; `c366963` for print-value.
§
Janet's `case` for multi-arity dispatch: `(defn f [& args] (case (length args) 1 ... 2 ...))`. Used in core-derive, core-isa?, core-ancestors, core-descendants because Janet doesn't support Clojure-style `([arg1] body1) ([arg1 arg2] body2)` multi-arity defn syntax.
