# Specification: reader forms + syntax-quote + metadata.
#
# Adapted from the jank test corpus (test/jank/{syntax-quote,metadata,reader-macro,
# call}); we keep our own copies since jank may diverge. Syntax-quoted symbols are
# qualified to clojure.core (matching jank/Clojure). Platform-specific reader forms
# (#uuid, #inst, ##Inf/##NaN, bigdecimal/biginteger/ratio) are omitted.
(use ../support/harness)

(defspec "reader / anonymous fn #()"
  ["no args"         "3"      "(#(+ 1 2))"]
  ["one arg %"       "6"      "(#(* % 2) 3)"]
  ["positional %1 %2" "[1 2]" "(#(do [%1 %2]) 1 2)"]
  ["rest %&"         "[1 2 3]" "(#(do %&) 1 2 3)"]
  ["fixed + rest"    "[2 3]"  "(#(do % %&) 1 2 3)"])
  # gap (jolt-6x1): %& with a higher positional (e.g. #(do %2 %&)) miscomputes the
  # fixed arity — (#(do %2 %&) 1 2 3) yields (2 3), should be [3] (rest after %2).

(defspec "reader / var-quote #'"
  ["var-quote = var" "true"   "(= (var str) #'str)"]
  ["is a var"        "true"   "(var? #'str)"]
  ["deref var-quote" "5"      "(do (def w 5) (deref #'w))"])

(defspec "reader / metadata ^"
  ["meta on quoted sym" "true" "(:foo (meta (quote ^:foo bar)))"]
  ["with-meta map"   "true"   "(:k (meta (with-meta {} {:k true})))"]
  ["with-meta vector" "true"  "(:k (meta (with-meta [] {:k true})))"]
  ["non-metadatable num" "nil" "(meta 100)"]
  ["non-metadatable str" "nil" "(meta \"\")"]
  ["non-metadatable bool" "nil" "(meta true)"])
  # gap (jolt-xl0): ^meta on collection literals ({}/[]/#{}) isn't attached —
  # (meta ^:foo {}) is nil; symbol meta + (with-meta …) work.

(defspec "reader / syntax-quote"
  ["plain literal"   "[1 2 3]" "`[1 2 3]"]
  ["gensym distinct" "true"   "(not= `meow# `meow#)"]
  ["gensym stable"   "true"   "(let [s `[meow# meow#]] (= (first s) (second s)))"]
  ["qualifies unresolved" "(quote user/foo)" "`foo"]
  ["unquote value"   "[1 2 3]" "(let [a [1 2 3]] `~a)"]
  # functional: the syntax-quoted call evaluates correctly (jolt-265: core syms are
  # left bare rather than qualified to clojure.core/, but still resolve at eval).
  ["unquote call evals" "6" "(let [a 5] (eval `(+ ~a 1)))"]
  ["splice call evals" "6"  "(let [a [1 2 3]] (eval `(+ ~@a)))"]
  ["splice in vector" "[1 2 3 0 1 2 3]" "(let [b [0] a [1 2 3] e []] `[~@e ~@a ~@b ~@a ~@e])"])
  # gap (jolt-edb): ~/~@ aren't processed inside set literals (`#{~@a} keeps the
  # unquote-splicing form literal).
