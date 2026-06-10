# Specification: sorted collections (sorted-map / sorted-set, subseq/rsubseq).
#
# sorted collections are first-class for the core ops (jolt-ti9): get/assoc/dissoc/
# conj/contains?/keys/vals/disj all work and preserve sort order, and a sorted coll
# is callable as a key-lookup fn. STILL TODO: the by-comparator constructors
# (sorted-map-by / sorted-set-by) ignore the supplied comparator (jolt-ti9). (vec
# coerces a seq to a vector so expecteds are vector literals, not quoted lists.)
(use ../support/harness)

(defspec "sorted / construction & ordering"
  ["sorted-set orders"   "[1 2 3]" "(vec (seq (sorted-set 3 1 2)))"]
  ["sorted-set dedupes"  "[1 2 3]" "(vec (seq (sorted-set 3 1 2 1 3)))"]
  ["sorted-set numeric"  "[1 2 10]" "(vec (seq (sorted-set 10 1 2)))"]
  ["sorted-map ordered entries" "[[:a 1] [:b 2] [:c 3]]" "(vec (seq (sorted-map :c 3 :a 1 :b 2)))"]
  ["first is min"        "1"       "(first (sorted-set 5 3 9 1))"])

(defspec "sorted / sorted?"
  ["sorted-set"      "true"   "(sorted? (sorted-set 1))"]
  ["sorted-map"      "true"   "(sorted? (sorted-map :a 1))"]
  ["plain set"       "false"  "(sorted? #{1})"]
  ["plain map"       "false"  "(sorted? {:a 1})"]
  ["vector"          "false"  "(sorted? [1 2])"])

(defspec "sorted / map ops"
  ["get hit"         "2"        "(get (sorted-map :a 1 :b 2) :b)"]
  ["get miss default" ":none"   "(get (sorted-map :a 1) :z :none)"]
  ["contains? yes"   "true"     "(contains? (sorted-map :a 1) :a)"]
  ["contains? no"    "false"    "(contains? (sorted-map :a 1) :z)"]
  ["assoc keeps order" "[[:a 1] [:b 2] [:c 3]]" "(vec (seq (assoc (sorted-map :c 3 :a 1) :b 2)))"]
  ["dissoc"          "[[:a 1] [:c 3]]" "(vec (seq (dissoc (sorted-map :a 1 :b 2 :c 3) :b)))"]
  ["conj entry"      "[[:a 1] [:z 9]]" "(vec (seq (conj (sorted-map :a 1) [:z 9])))"]
  ["keys sorted"     "[:a :b :c]" "(vec (keys (sorted-map :c 3 :a 1 :b 2)))"]
  ["vals by key"     "[1 2 3]"  "(vec (vals (sorted-map :c 3 :a 1 :b 2)))"]
  ["map as fn"       "2"        "((sorted-map :a 1 :b 2) :b)"]
  ["map as fn miss"  ":d"       "((sorted-map :a 1) :z :d)"])

(defspec "sorted / set ops"
  ["get present"     "2"        "(get (sorted-set 1 2 3) 2)"]
  ["get absent"      ":none"    "(get (sorted-set 1 2 3) 9 :none)"]
  ["contains? yes"   "true"     "(contains? (sorted-set 1 2 3) 2)"]
  ["contains? no"    "false"    "(contains? (sorted-set 1 2 3) 9)"]
  ["conj keeps order" "[0 1 2 3 5]" "(vec (seq (conj (sorted-set 1 2 3) 5 0)))"]
  ["disj"            "[1 3]"    "(vec (seq (disj (sorted-set 1 2 3) 2)))"]
  ["set as fn"       "3"        "((sorted-set 1 2 3) 3)"]
  ["set as fn miss"  "nil"      "((sorted-set 1 2 3) 9)"])

(defspec "sorted / by comparator"
  ["sorted-set-by desc"  "[10 3 2 1]" "(vec (seq (sorted-set-by > 1 3 2 10)))"]
  ["sorted-map-by desc"  "[[3 :c] [2 :b] [1 :a]]" "(vec (seq (sorted-map-by > 1 :a 3 :c 2 :b)))"]
  ["conj keeps comparator" "[5 3 2 1 0]" "(vec (seq (conj (sorted-set-by > 1 3 2) 5 0)))"]
  ["assoc keeps comparator" "[3 2 1]" "(vec (keys (assoc (sorted-map-by > 1 :a 3 :c) 2 :b)))"]
  ["disj keeps comparator" "[3 1]"   "(vec (seq (disj (sorted-set-by > 1 2 3) 2)))"]
  ["by-comparator is sorted?" "true" "(sorted? (sorted-set-by > 1 2))"])

(defspec "sorted / subseq & rsubseq"
  ["subseq >="       "[3 4 5]" "(vec (subseq (sorted-set 1 2 3 4 5) >= 3))"]
  ["subseq <"        "[1 2]"   "(vec (subseq (sorted-set 1 2 3 4 5) < 3))"]
  ["subseq range"    "[2 3 4]" "(vec (subseq (sorted-set 1 2 3 4 5) > 1 < 5))"]
  ["rsubseq <="      "[3 2 1]" "(vec (rsubseq (sorted-set 1 2 3 4 5) <= 3))"])
