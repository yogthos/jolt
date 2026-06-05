# Specification: transients (mutable scratch collections frozen by persistent!).
(use ../support/harness)

(defspec "transient / vector"
  ["conj! then persistent!" "[1 2]"     "(persistent! (conj! (conj! (transient []) 1) 2))"]
  ["reduce conj!"           "[0 1 2 3 4]" "(persistent! (reduce conj! (transient []) (range 5)))"]
  ["conj! many args"        "[1 2 3]"    "(persistent! (conj! (transient [1]) 2 3))"]
  ["assoc! existing"        "[1 9 3]"    "(persistent! (assoc! (transient [1 2 3]) 1 9))"]
  ["assoc! at count grows"  "[1 2 3]"    "(persistent! (assoc! (transient [1 2]) 2 3))"]
  ["pop!"                   "[1 2]"      "(persistent! (pop! (transient [1 2 3])))"]
  ["from existing vector"   "[1 2 3 4]"  "(persistent! (conj! (transient [1 2 3]) 4))"]
  ["count"                  "3"          "(count (transient [1 2 3]))"]
  ["nth"                    "2"          "(nth (transient [1 2 3]) 1)"]
  ["get"                    "2"          "(get (transient [1 2 3]) 1)"]
  ["persistent! is a vector" "true"      "(vector? (persistent! (transient [1])))"]
  ["transient? true"        "true"       "(transient? (transient []))"]
  ["transient? false"       "false"      "(transient? [1 2])"])

(defspec "transient / map"
  ["assoc! then persistent!" "{:a 1, :b 2}" "(persistent! (assoc! (assoc! (transient {}) :a 1) :b 2))"]
  ["assoc! many"            "{:a 1, :b 2}" "(persistent! (assoc! (transient {}) :a 1 :b 2))"]
  ["dissoc!"                "{:b 2}"     "(persistent! (dissoc! (transient {:a 1 :b 2}) :a))"]
  ["conj! map entry"        "{:a 1}"     "(persistent! (conj! (transient {}) [:a 1]))"]
  ["from existing map"      "{:a 1, :b 2}" "(persistent! (assoc! (transient {:a 1}) :b 2))"]
  ["get"                    "1"          "(get (transient {:a 1}) :a)"]
  ["get missing default"    ":x"         "(get (transient {:a 1}) :z :x)"]
  ["contains?"              "true"       "(contains? (transient {:a 1}) :a)"]
  ["count"                  "2"          "(count (transient {:a 1 :b 2}))"]
  ["collection key by value" ":v"        "(get (persistent! (assoc! (transient {}) [1 2] :v)) [1 2])"]
  ["persistent! is a map"   "true"       "(map? (persistent! (transient {:a 1})))"]
  ["reduce build"           "{0 0, 1 1, 2 2}" "(persistent! (reduce (fn [t i] (assoc! t i i)) (transient {}) (range 3)))"])

(defspec "transient / set"
  ["conj! dedups"           "#{1 2 3}"   "(persistent! (conj! (transient #{}) 1 2 2 3))"]
  ["disj!"                  "#{1 3}"     "(persistent! (disj! (transient #{1 2 3}) 2))"]
  ["from existing set"      "#{1 2 3}"   "(persistent! (conj! (transient #{1 2}) 3))"]
  ["contains?"              "true"       "(contains? (transient #{1 2}) 1)"]
  ["count"                  "2"          "(count (transient #{1 2}))"]
  ["persistent! is a set"   "true"       "(set? (persistent! (transient #{1})))"]
  ["map elements by value"  "1"          "(count (persistent! (conj! (transient #{}) {:a 1} (hash-map :a 1))))"])

(defspec "transient / immutability of source"
  ["source vector unchanged" "true"
   "(let [v [1 2 3] _ (persistent! (conj! (transient v) 4))] (= v [1 2 3]))"]
  ["source map unchanged"    "true"
   "(let [m {:a 1} _ (persistent! (assoc! (transient m) :b 2))] (= m {:a 1}))"])
