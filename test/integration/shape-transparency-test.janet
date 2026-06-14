# Shape-record transparency (jolt-t34 Round 1). A shape-rec is the compiler's
# cheap representation for a constant-key map literal — a Janet tuple
# [descriptor v0 v1 ...]. Every map operation must treat it EXACTLY like the
# equivalent struct map, so a shape value is transparent wherever it flows.
# These build shape-recs directly via the runtime (shape-for + tuple) and
# assert each op matches the struct map's behavior.
(use ../../src/jolt/types)
(use ../../src/jolt/core)

(var fails 0)
(defn check [label got want]
  (if (deep= got want) (print "  ok   " label)
    (do (++ fails) (printf "  FAIL %s: got %j want %j" label got want))))

# {:a 1 :b 2} as a shape-rec and as a struct — they must be indistinguishable
(def SH (shape-for [:a :b]))
(def r (tuple SH 1 2))
(def s {:a 1 :b 2})

# --- access ------------------------------------------------------------------
(check "get hit"        (core-get r :a nil) 1)
(check "get hit 2"      (core-get r :b nil) 2)
(check "get miss"       (core-get r :z :d) :d)
(check "count"          (core-count r) 2)
(check "contains? hit"  (core-contains? r :a) true)
(check "contains? miss" (core-contains? r :z) false)
(check "map?"           (core-map? r) true)

# --- update (returns something that reads back correctly) --------------------
(check "assoc existing" (core-get (core-assoc r :a 9) :a nil) 9)
(check "assoc new key"  (core-get (core-assoc r :c 3) :c nil) 3)
(check "assoc keeps others" (core-get (core-assoc r :c 3) :b nil) 2)
(check "dissoc"         (core-get (core-dissoc r :a) :a :gone) :gone)
(check "dissoc keeps"   (core-get (core-dissoc r :a) :b nil) 2)

# --- enumeration: entries via the central seq normalizer (what keys/vals/seq/
# reduce-kv in the overlay all flow through) — order-independent ---------------
(defn entryset [m] (sorted (map |(string/format "%j" $) (realize-for-iteration m))))
(check "entries match struct" (entryset r) (entryset s))
(check "count of seq"  (length (core-seq r)) 2)
(check "first is a 2-entry"   (length (core-first r)) 2)

# --- equality: a shape-rec equals the same struct map and vice versa ---------
(check "= shape vs struct"  (jolt-equal? r s) true)
(check "= struct vs shape"  (jolt-equal? s r) true)
(check "= shape vs shape"   (jolt-equal? r (tuple (shape-for [:a :b]) 1 2)) true)
(check "not= diff value"    (jolt-equal? r (tuple (shape-for [:a :b]) 1 9)) false)
(check "not= diff shape"    (jolt-equal? r (tuple (shape-for [:a :b :c]) 1 2 3)) false)
(check "not= vs vector"     (jolt-equal? r [1 2]) false)

# --- IFn: a map is callable as a key lookup ----------------------------------
(check "call as fn"     (jolt-call r :a) 1)
(check "call as fn miss default" (jolt-call r :z :d) :d)

# --- nil/false values are present (shape-recs store them positionally) --------
(def rn (tuple (shape-for [:a :b]) nil false))
(check "nil value present"   (core-contains? rn :a) true)
(check "nil value get"       (core-get rn :a :d) nil)
(check "false value get"     (core-get rn :b :d) false)
(check "count with nils"     (core-count rn) 2)

(if (> fails 0)
  (error (string "shape-transparency: " fails " failing check(s)"))
  (print "\nShape transparency passed!"))
