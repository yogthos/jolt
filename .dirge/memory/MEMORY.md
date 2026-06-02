SCI added as git submodule at `vendor/sci` (github.com/borkdude/sci). Path to SCI sources: `vendor/sci/src/sci/`. The original `/Users/yogthos/src/sci` path is now superseded.
§
Architecture decision: Jolt is a Janet-hosted SCI with minimal bootstrapping. Jolt's evaluator + reader form the runtime; SCI's `clojure.core` namespace is populated by loading all 9 SCI source files. `sci.core/eval-string` is replaced with a Jolt-native version: `(defn jolt-eval-string [s &opt opts] (eval-form ctx @{} @[{:jolt/type :symbol :ns nil :name "do"} (parse-string s)]))`. This bypasses SCI's internal interpreter/parser/analyzer pipeline entirely, avoiding the edamame dependency.
§
gensym in core.janet: uses `@{}` mutable table counter `gensym_counter`. Takes optional prefix string (default "G__"). `core-doto` uses gensym for the object symbol, expands to `(let* [sym obj] (. sym method args)... sym)`. `core-defrecord` generates `->TypeName` positional constructor. `core-name` returns string for keywords (`(string kw)`) or symbol name field.
§
SCI added as git submodule at vendor/sci. Load path: vendor/sci/src/sci/*.cljc (not impl/lang.cljc — lang.cljc is at top level under src/sci/). Internal namespaces that need edamame shims: interop.cljc, opts.cljc, parser.cljc, analyzer.cljc, interpreter.cljc. Parser requires edamame.core and clojure.tools.reader.reader-types stubs.
§
Constructor call resolution (ClassName. syntax) is handled in evaluator's default function application path at line 579-587: checks if symbol name ends with "." (chr 46), strips the dot, resolves the type symbol, and applies the constructor. This means `(sci.lang.Var. 1 2 3)` resolves `sci.lang.Var.` → looks up `sci.lang/Var` → gets the deftype constructor function → applies args. No special form needed.
