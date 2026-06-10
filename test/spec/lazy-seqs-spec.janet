# Specification: lazy sequences.
(use ../support/harness)

(defspec "lazy / construction & laziness"
  ["lazy-seq value"     "[1 2 3]"  "(take 3 (lazy-seq (cons 1 (lazy-seq (cons 2 (lazy-seq (cons 3 nil)))))))"]
  ["not eagerly evaluated" "0"     "(let [c (atom 0)] (lazy-seq (swap! c inc) nil) @c)"]
  ["realized on demand"  "1"       "(let [c (atom 0) s (lazy-seq (swap! c inc) [1])] (first s) @c)"]
  ["lazy-cat"           "[0 1 2 3]" "(lazy-cat [0 1] [2 3])"]
  ["doall forces"       "[2 3 4]"  "(doall (map inc [1 2 3]))"]
  ["dorun returns nil"  "nil"      "(dorun (map inc [1 2 3]))"])

(defspec "lazy / infinite"
  ["take from repeat"   "[7 7 7]"  "(take 3 (repeat 7))"]
  ["take from iterate"  "[1 2 4 8]" "(take 4 (iterate (fn [x] (* 2 x)) 1))"]
  ["take from cycle"    "[1 2 1 2]" "(take 4 (cycle [1 2]))"]
  ["take from range"    "[0 1 2]"  "(take 3 (range))"]
  ["drop then take"     "[5 6 7]"  "(take 3 (drop 5 (range)))"]
  ["filter infinite"    "[0 2 4]"  "(take 3 (filter even? (range)))"]
  ["map infinite"       "[0 1 4]"  "(take 3 (map (fn [x] (* x x)) (range)))"]
  ["nth of infinite"    "100"      "(nth (range) 100)"])

(defspec "lazy / self-referential"
  ["self-ref ones"      "[1 1 1 1 1]" "(do (def ones (lazy-seq (cons 1 ones))) (take 5 ones))"]
  ["self-ref nats"      "[0 1 2 3 4]" "(do (def nats (lazy-cat [0] (map inc nats))) (take 5 nats))"]
  ["self-ref fib"       "[0 1 1 2 3 5 8 13 21 34]"
   "(do (def fib (lazy-cat [0 1] (map + (rest fib) fib))) (take 10 fib))"])

(defspec "lazy / realized?"
  ["unrealized"         "false"    "(realized? (lazy-seq (cons 1 nil)))"]
  ["realized after"     "true"     "(let [s (lazy-seq (cons 1 nil))] (first s) (realized? s))"]
  ["body runs once"     "1"        "(let [c (atom 0) s (lazy-seq (do (swap! c inc) [1 2 3]))] (seq s) (seq s) @c)"])

# Independent walks over the SAME lazy seq share realization: each node's rest
# wrapper is memoized (ls-rest-cached), so the shared rest-thunks run exactly
# once. Pre-fix, every walk after the first re-ran the thunks — duplicating
# side effects, and a doall'd seq of futures re-spawned them serially on the
# deref walk (which is how it surfaced, via pmap).
(defspec "lazy-seq / realization is shared across walks"
  ["effects run once across three walks" "3"
   "(let [a (atom 0) s (map (fn [x] (swap! a inc) x) [1 2 3])] (doall s) (dorun s) (vec s) (deref a))"]
  ["values stable across walks" "true"
   "(let [s (map inc [1 2 3])] (= (vec s) (vec s) [2 3 4]))"]
  ["filter effects once" "4"
   "(let [a (atom 0) s (filter (fn [x] (swap! a inc) (odd? x)) [1 2 3 4])] (dorun s) (count s) (deref a))"])
