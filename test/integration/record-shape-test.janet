# Records as shape-recs (jolt-t34 R3). A user record (defrecord/deftype) under
# JOLT_SHAPE is a shape-rec whose descriptor ALSO carries :type (the type tag),
# laid out in DECLARED field order. These build records directly via the runtime
# (make-record) and assert that every map/record operation treats them the way
# Clojure does — and crucially that type identity is preserved (a record is not
# a plain map, and two records are equal only when their types match).
(use ../../src/jolt/types)
(use ../../src/jolt/core)

(var fails 0)
(defn check [label got want]
  (if (deep= got want) (print "  ok   " label)
    (do (++ fails) (printf "  FAIL %s: got %j want %j" label got want))))

# (defrecord Point [x y]) instance (->Point 1 2)
(def P (make-record "my.Point" [:x :y] [1 2]))

# --- it IS a shape-rec, and reports its type ---------------------------------
(check "shape-rec?"        (shape-rec? P) true)
(check "record-tag"        (record-tag P) "my.Point")
(check "map?"              (core-map? P) true)

# --- field access in declared order ------------------------------------------
(check "get x"             (core-get P :x nil) 1)
(check "get y"             (core-get P :y nil) 2)
(check "get miss default"  (core-get P :z :d) :d)
(check "count"             (core-count P) 2)
(check "contains?"         (core-contains? P :x) true)

# --- the virtual :jolt/deftype key keeps every (get obj :jolt/deftype) site
# (record?/dispatch) working without special-casing each one ------------------
(check "virtual deftype"   (core-get P :jolt/deftype nil) "my.Point")

# --- assoc preserves the type: in place for a declared field, and grows a
# slot Clojure-style for a new key (the result is still a record) -------------
(def P2 (core-assoc P :x 9))
(check "assoc field tag"   (record-tag P2) "my.Point")
(check "assoc field val"   (core-get P2 :x nil) 9)
(check "assoc keeps other" (core-get P2 :y nil) 2)
(def P3 (core-assoc P :z 3))
(check "assoc new tag"     (record-tag P3) "my.Point")
(check "assoc new val"     (core-get P3 :z nil) 3)
(check "assoc new keeps"   (core-get P3 :x nil) 1)

# --- dissoc of a declared field demotes to a plain map (Clojure semantics) ----
(def D (core-dissoc P :x))
(check "dissoc demotes"    (record-tag D) nil)
(check "dissoc gone"       (core-get D :x :gone) :gone)
(check "dissoc keeps"      (core-get D :y nil) 2)

# --- equality is TYPE-AWARE: same type + same fields equal; a different type
# or a plain map with the same fields is NOT equal ----------------------------
(check "= same type"       (jolt-equal? P (make-record "my.Point" [:x :y] [1 2])) true)
(check "not= diff field"   (jolt-equal? P (make-record "my.Point" [:x :y] [1 9])) false)
(check "not= diff type"    (jolt-equal? P (make-record "my.Other" [:x :y] [1 2])) false)
(check "not= record vs map" (jolt-equal? P {:x 1 :y 2}) false)
(check "not= map vs record" (jolt-equal? {:x 1 :y 2} P) false)

# --- printing: Clojure record syntax #ns.Type{:k v, ...}, fields in order -----
(check "pr record"         (core-pr-str1 P) "#my.Point{:x 1, :y 2}")

(if (> fails 0)
  (error (string "record-shape: " fails " failing check(s)"))
  (print "\nRecord shape passed!"))
