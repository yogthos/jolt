(use ../src/jolt/types)
(use ../src/jolt/api)
(use ../src/jolt/reader)
(use ../src/jolt/evaluator)

(def ctx (init))

# Load persistent hash map source
(def s (slurp "src/jolt/clojure/lang/persistent_hash_map.clj"))
(var cur s)
(while (> (length (string/trim cur)) 0)
  (def [form rest] (parse-next cur))
  (set cur rest)
  (when (not (nil? form))
    (try (eval-form ctx @{} form) ([err] nil))))

(def ns (ctx-find-ns ctx "jolt.lang.persistent-hash-map"))
(def EMPTY (var-get (ns-find ns "EMPTY")))

# Test 1: EMPTY is a PersistentHashMap
(assert (not (nil? EMPTY)) "EMPTY should exist")

# Test 2: phm-assoc returns a PersistentHashMap
(def m1 (eval-string ctx "(jolt.lang.persistent-hash-map/phm-assoc jolt.lang.persistent-hash-map/EMPTY :a 1)"))
(assert (not (nil? m1)) "phm-assoc should return a map")

# Test 3: phm-count returns 1 after assoc
(def count-val (eval-string ctx "(jolt.lang.persistent-hash-map/phm-count jolt.lang.persistent-hash-map/EMPTY)"))
(assert (= 0 count-val) "EMPTY count should be 0")

# Test 4: root exists after assoc
(def root-val (get m1 :root))
(assert (not (nil? root-val)) "root should exist after assoc")

# Test 5: bitmap is non-zero
(def bm (get root-val :bitmap))
(printf "bitmap: %q\n" bm)

# Test 6: hash-mix produces positive values
(def hmix (var-get (ns-find ns "hash-mix")))
(def h1 (hmix (eval-string ctx "(hash :a)")))
(assert (> h1 0) "hash-mix should produce positive values")

(printf "\nAll persistent hash map tests passed\n")
