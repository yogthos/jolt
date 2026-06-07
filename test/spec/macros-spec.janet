# Specification: macros, quoting and syntax-quote.
(use ../support/harness)

(defspec "macros / quoting"
  ["quote symbol"       "(quote a)"         "(quote a)"]
  ["quote list"         "[1 2 3]"     "(quote (1 2 3))"]
  ["quote nested"       "[1 [2 3]]"   "(quote (1 (2 3)))"]
  ["quote sugar"        "'a"          "'a"]
  ["syntax-quote literal" "[1 2]"     "`[1 2]"]
  ["unquote"            "[1 2 3]"     "(let [x 2] `[1 ~x 3])"]
  ["unquote-splicing"   "[1 2 3 4]"   "(let [xs [2 3]] `[1 ~@xs 4])"]
  ["unquote in list"    "[3]"         "(let [x 3] `(~x))"]
  ["syntax-quote symbol qualifies" "true" "(symbol? `foo)"])

(defspec "macros / defmacro"
  ["simple macro"       "3"
   "(do (defmacro m [a b] `(+ ~a ~b)) (m 1 2))"]
  ["macro unless"       "1"
   "(do (defmacro unless [c body] `(if ~c nil ~body)) (unless false 1))"]
  ["macro with body splice" "6"
   "(do (defmacro msum [& xs] `(+ ~@xs)) (msum 1 2 3))"]
  ["macroexpand-1"      "true"
   "(do (defmacro m [x] `(inc ~x)) (list? (macroexpand-1 '(m 5))))"]
  ["gensym unique"      "false"
   "(= (gensym) (gensym))"]
  ["gensym# in template" "true"
   "(do (defmacro m [] `(let [x# 1] x#)) (= 1 (m)))"])

# Core macros ported from Janet to the Clojure overlay (jolt-1j0 phase 3,
# jolt-core/clojure/core/30-macros.clj).
(defspec "macros / core-overlay"
  ["if-not true branch"  ":then"  "(if-not false :then :else)"]
  ["if-not else branch"  ":else"  "(if-not true :then :else)"]
  ["if-not no else"      "nil"    "(if-not true :then)"]
  ["if-not no else hit"  ":then"  "(if-not false :then)"]
  ["comment -> nil"      "nil"    "(comment a b c)"]
  ["comment in do"       "42"     "(do (comment ignored) 42)"]
  ["if-let then"         "6"      "(if-let [x 5] (inc x) :none)"]
  ["if-let else"         ":none"  "(if-let [x nil] (inc x) :none)"]
  ["if-let else scope"   "9"      "(let [x 9] (if-let [x nil] :t x))"]
  ["if-some zero"        "1"      "(if-some [x 0] (inc x) :none)"]
  ["if-some nil"         ":none"  "(if-some [x nil] x :none)"]
  ["when-some multi"     "14"     "(when-some [x 7] (inc x) (* x 2))"]
  ["when-some nil"       "nil"    "(when-some [x nil] x)"]
  ["while loop"          "3"      "(let [a (atom 0)] (while (< @a 3) (swap! a inc)) @a)"]
  ["dotimes sum"         "10"     "(let [a (atom 0)] (dotimes [i 5] (swap! a + i)) @a)"])
