# Specification: sorted collections (sorted-map / sorted-set, subseq/rsubseq).
#
# NOTE: sorted collections are only partially first-class in Jolt — get/conj/assoc/
# contains?/keys/vals on a sorted coll, and the by-comparator constructors, are NOT
# yet wired up (jolt-ti9). This spec pins the behavior that DOES work (construction,
# SEQ ordering, subseq/rsubseq, sorted?, first) so it can't regress; the broken ops
# are tracked in jolt-ti9. (vec coerces the seq to a vector so expecteds are vector
# literals rather than quoted lists.)
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

(defspec "sorted / subseq & rsubseq"
  ["subseq >="       "[3 4 5]" "(vec (subseq (sorted-set 1 2 3 4 5) >= 3))"]
  ["subseq <"        "[1 2]"   "(vec (subseq (sorted-set 1 2 3 4 5) < 3))"]
  ["subseq range"    "[2 3 4]" "(vec (subseq (sorted-set 1 2 3 4 5) > 1 < 5))"]
  ["rsubseq <="      "[3 2 1]" "(vec (rsubseq (sorted-set 1 2 3 4 5) <= 3))"])
