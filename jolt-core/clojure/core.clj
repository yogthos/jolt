;; The Clojure portion of clojure.core. Loaded into the clojure.core namespace at
;; init (api/init), AFTER the Janet primitives are interned by core/init-core!,
;; and compiled by the self-hosted pipeline (analyzer -> IR -> Janet back end).
;;
;; This is the Phase 4 kernel-shrink seam: fns expressible in plain Clojure on top
;; of the remaining Janet primitives move here from core.janet, one at a time,
;; each compiled by the prior stage. Anything here must depend only on core vars
;; already interned by init-core! (and on other overlay fns defined above it).
;;
;; Safe-to-move rule: a fn can move here only if it is (1) NOT in
;; compiler/core-renames (that map emits core-X Janet symbols directly), (2) has
;; no internal Janet callers of its core-X binding, and (3) is NOT used by the
;; self-hosted compiler itself (jolt-core/jolt/*.clj) — the compiler has to
;; compile this overlay, so anything it calls must already exist as a Janet
;; primitive. (That last rule is why `second`, used by analyzer.clj, stays in
;; Janet even though it has no Janet callers.)

(defn ffirst [coll] (first (first coll)))
(defn nfirst [coll] (next (first coll)))
(defn fnext  [coll] (first (next coll)))
(defn nnext  [coll] (next (next coll)))

;; Canonical Clojure defs: pure first/next/loop/recur, no Janet realize-for-iteration.
(defn last [s]
  (if (next s) (recur (next s)) (first s)))

(defn butlast [s]
  (loop [ret [] s s]
    (if (next s)
      (recur (conj ret (first s)) (next s))
      (seq ret))))
