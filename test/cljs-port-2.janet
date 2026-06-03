(use ../src/jolt/api)
(defn ct-eval [ctx s] (eval-string ctx s))
(print "=== CLJS Ported Part 2 ===")

(print "12: atoms...")
(let [ctx (init)]
  (assert (= 0 (ct-eval ctx "(deref (atom 0))")) "deref")
  (assert (= 1 (ct-eval ctx "(let [a (atom 0)] (swap! a inc) (deref a))")) "swap!")
  (assert (= true (ct-eval ctx "(atom? (atom 0))")) "atom?"))
(print "  ok")

(print "13: special forms...")
(let [ctx (init)]
  (assert (= 30 (ct-eval ctx "(let [x 10 y 20] (+ x y))")) "let")
  (assert (= :a (ct-eval ctx "(if true :a :b)")) "if true")
  (assert (= :b (ct-eval ctx "(if false :a :b)")) "if false")
  (assert (= 2 (ct-eval ctx "(do 1 2)")) "do")
  (assert (= 3 (ct-eval ctx "(loop [x 0] (if (< x 3) (recur (inc x)) x))")) "loop")
  (assert (= "caught" (ct-eval ctx "(try (throw 42) (catch Exception e \"caught\"))")) "try catch"))
(print "  ok")

(print "14: macros...")
(let [ctx (init)]
  (ct-eval ctx "(defn add [a b] (+ a b))")
  (assert (= 7 (ct-eval ctx "(add 3 4)")) "defn")
  (assert (= 42 (ct-eval ctx "(when true 42)")) "when")
  (assert (= 3 (ct-eval ctx "(and 1 2 3)")) "and")
  (assert (= 1 (ct-eval ctx "(or 1 2 3)")) "or")
  (assert (= 49 (ct-eval ctx "((fn [x] (* x x)) 7)")) "fn"))
(print "  ok")

(print "15: constructors...")
(let [ctx (init)]
  (assert (= 3 (ct-eval ctx "(count (vector 1 2 3))")) "vector count")
  (assert (= 2 (ct-eval ctx "(count (hash-map :a 1 :b 2))")) "hash-map count")
  (assert (= 3 (ct-eval ctx "(count (hash-set 1 2 3))")) "hash-set count")
  (assert (= 3 (ct-eval ctx "(count (zipmap [:a :b :c] [1 2 3]))")) "zipmap count"))
(print "  ok")

(print "\nAll CLJS Ported Part 2 tests passed!")
