# Specification: the last missing-portable core vars (jolt-brh):
# extenders, find-keyword, inst-ms*, read+string, with-local-vars, with-open,
# with-precision. Documented jolt divergences: find-keyword always finds (jolt
# keywords have no intern table — babashka does the same); with-precision
# evaluates its body with the precision ignored (numbers are doubles, no
# BigDecimal context); with-open closes via the value's :close fn or a host
# file (no .close interop on the Janet host).
(use ../support/harness)

(defspec "core / find-keyword + inst-ms*"
  ["find-keyword"         ":a"     "(find-keyword \"a\")"]
  ["find-keyword 2-arity" ":n/a"   "(find-keyword \"n\" \"a\")"]
  ["find-keyword = keyword" "true" "(= (find-keyword \"x\") :x)"]
  ["inst-ms*"             "true"   "(= (inst-ms* #inst \"2020-01-01T00:00:00Z\") (inst-ms #inst \"2020-01-01T00:00:00Z\"))"]
  ["inst-ms* value"       "0"      "(inst-ms* #inst \"1970-01-01T00:00:00Z\")"])

(defspec "core / with-local-vars"
  ["var-get initial"   "1"       "(with-local-vars [x 1] (var-get x))"]
  ["var-set"           "2"       "(with-local-vars [x 1] (var-set x 2) (var-get x))"]
  ["two vars"          "[1 2]"   "(with-local-vars [a 1 b 2] [(var-get a) (var-get b)])"]
  ["vars are values"   "5"       "(with-local-vars [x 0] (let [bump (fn [v] (var-set v (+ 5 (var-get v))))] (bump x) (var-get x)))"]
  ["init sees outer"   "3"       "(let [y 3] (with-local-vars [x y] (var-get x)))"]
  ["body result"       ":done"   "(with-local-vars [x 1] :done)"])

(defspec "core / with-open"
  ["body result"        ":r"     "(let [log (atom [])] (with-open [c {:close (fn [] (swap! log conj :closed))}] :r))"]
  ["close runs"         "[:closed]" "(let [log (atom [])] (with-open [c {:close (fn [] (swap! log conj :closed))}] :r) (deref log))"]
  ["close on throw"     "[:closed]" "(let [log (atom [])] (try (with-open [c {:close (fn [] (swap! log conj :closed))}] (throw (ex-info \"boom\" {}))) (catch Exception e nil)) (deref log))"]
  ["nested close order" "[:inner :outer]" "(let [log (atom [])] (with-open [a {:close (fn [] (swap! log conj :outer))} b {:close (fn [] (swap! log conj :inner))}] :r) (deref log))"]
  ["zero bindings"      ":r"     "(with-open [] :r)"]
  ["binding visible"    "5"      "(with-open [c {:close (fn [] nil) :v 5}] (:v c))"])

(defspec "core / with-precision"
  ["body evaluates"     "3.14"   "(with-precision 3 3.14)"]
  ["multiple body forms" "2"     "(with-precision 10 1 2)"]
  ["rounding arg accepted" "1.5" "(with-precision 4 :rounding :half-up 1.5)"]
  ["arithmetic"         "2"      "(with-precision 5 (+ 1 1))"])

(defspec "core / read+string"
  ["form and text"      "true"   "(let [[v s] (with-in-str \"42 rest\" (read+string))] (and (= v 42) (string? s)))"]
  ["form value"         "(quote (+ 1 2))" "(first (with-in-str \"(+ 1 2)\" (read+string)))"]
  ["text covers the form" "true"  "(let [[v s] (with-in-str \"  [1 2] tail\" (read+string))] (and (= v [1 2]) (> (count s) 3)))"]
  ["advances the stream" "[1 2]" "(with-in-str \"1 2\" [(first (read+string)) (first (read+string))])"]
  ["EOF throws"         :throws  "(with-in-str \"\" (read+string))"]
  ["eof-value arity"    ":done"  "(first (with-in-str \"\" (read+string *in* false :done)))"])

(defspec "core / extenders"
  ["lists extended type" "[\"user.Rx\"]"
   "(do (defprotocol Px (pm [x])) (defrecord Rx [] Px (pm [x] 1)) (mapv str (extenders Px)))"]
  ["nil when none"      "nil"
   "(do (defprotocol Py (pn [x])) (extenders Py))"]
  ["seq of tags"        "true"
   "(do (defprotocol Pz (pz [x])) (defrecord Rz [] Pz (pz [x] 1)) (and (seq (extenders Pz)) (= 1 (count (extenders Pz)))))"])
