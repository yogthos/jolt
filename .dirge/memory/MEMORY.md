`:keys` destructuring in `let*` uses `:keys` keyword (not `"keys"` string) to look up the vector of keys: `{:keys [a b]}` → `(get pat :keys)` returns `(a b)` tuple where each is a keyword. Bind each using `(get val (keyword kname))`.
§
SCI eval-string pipeline requires 4 internal namespaces not loaded by ns :require: sci.impl.interpreter, sci.impl.parser, sci.impl.analyzer, sci.impl.opts. Their source files must be loaded separately. After loading all 9 SCI source files, these namespaces have 0 bindings. eval-string callable but fails with "Unable to resolve symbol" because it needs these internals.
§
Edamame shim lives in core.janet, embedded alongside core bindings. Uses `make-string-reader` to create `@{:s str :pos 0 :line 1 :col 1}` reader tables. `shim-edamame-eof` returns `:edamame/eof` keyword. `init-edamame-shim!` takes `ctx`, `parse-str` (e.g. Jolt's `parse-string`), and `read-f` (e.g. Jolt's `read-form`) as arguments to avoid requiring `./reader` from `core.janet`. Line/col tracking increments on newline (chr 10).
§
SCI added as git submodule at `vendor/sci` (github.com/borkdude/sci). Path to SCI sources: `vendor/sci/src/sci/`. The original `/Users/yogthos/src/sci` path is now superseded.
§
Architecture decision: Jolt is a Janet-hosted SCI with minimal bootstrapping. Jolt's evaluator + reader form the runtime; SCI's `clojure.core` namespace is populated by loading all 9 SCI source files. `sci.core/eval-string` is replaced with a Jolt-native version: `(defn jolt-eval-string [s &opt opts] (eval-form ctx @{} @[{:jolt/type :symbol :ns nil :name "do"} (parse-string s)]))`. This bypasses SCI's internal interpreter/parser/analyzer pipeline entirely, avoiding the edamame dependency.
§
gensym in core.janet: uses `@{}` mutable table counter `gensym_counter`. Takes optional prefix string (default "G__"). `core-doto` uses gensym for the object symbol, expands to `(let* [sym obj] (. sym method args)... sym)`. `core-defrecord` generates `->TypeName` positional constructor. `core-name` returns string for keywords (`(string kw)`) or symbol name field.
