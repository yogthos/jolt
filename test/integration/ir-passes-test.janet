# IR pass pipeline (jolt-2om, nanopass-lite): jolt.passes/run-passes applies
# pure IR->IR rewrites between the analyzer and the back end. The first pass
# is constant folding — it computes with the ACTUAL jolt fns, so folded
# results match runtime semantics by construction.
(import ../../src/jolt/api :as api)
(import ../../src/jolt/backend :as backend)
(import ../../src/jolt/reader :as reader)

(print "IR passes (constant folding)...")
(def ctx (api/init-cached {:compile? true}))
(defn ir [src] (backend/analyze-form ctx (reader/parse-string src)))

(defn check-const [src want]
  (def n (ir src))
  (assert (= :const (n :op)) (string src " folds to a constant"))
  (assert (= want (n :val)) (string src " folds to " (string/format "%q" want))))

(check-const "(+ 1 2 3)" 6)
(check-const "(* 2 (+ 3 4))" 14)
(check-const "(quot 7 2)" 3)
(check-const "(mod -7 3)" 2)
(check-const "(if (< 1 2) :yes :no)" :yes)
# dead-branch elimination: the untaken branch never evaluates
(check-const "(if false (this-would-not-resolve) 2)" 2)

# non-constants stay calls; folding must be conservative
(assert (= :invoke ((ir "(+ x 2)") :op)) "free var stays a call")
(assert (= :invoke ((ir "(mod x 0)") :op)) "non-const args stay calls")
# a fold that would THROW is left for runtime
(assert (= :invoke ((ir "(mod 5 0)") :op)) "throwing fold left to runtime")

# and the folded code evaluates identically (3-mode conformance covers the
# broader matrix; this pins a couple end-to-end)
(assert (= 6 (api/eval-string ctx "(+ 1 2 3)")) "folded eval")
(assert (= :yes (api/eval-string ctx "(if (< 1 2) :yes :no)")) "folded if eval")
(print "IR passes passed!")
