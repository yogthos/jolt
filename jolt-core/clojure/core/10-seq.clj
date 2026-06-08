;; clojure.core — seq tier. Pure-Clojure leaf sequence fns on top of the kernel
;; tier (00-kernel) and the Janet seed. Loaded after the kernel tier; in compile
;; mode these self-host through the now-built analyzer (interpreted otherwise).
;;
;; Migration rule for adding fns here: the fn must (1) NOT be in
;; compiler/core-renames (that map emits core-X Janet symbols directly), (2) have
;; no internal Janet callers of its core-X binding, and (3) NOT be used by the
;; self-hosted compiler (jolt-core/jolt/*.clj). Compiler-facing structural fns go
;; in the kernel tier (00-kernel) instead — see its header.

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

(defn- mapcat-step [rs cur]
  (lazy-seq
    (if cur
      (let [s (seq cur)]
        (if s
          (cons (first s) (mapcat-step rs (rest s)))
          (mapcat-step rs nil)))
      (let [s (seq rs)]
        (if s
          (let [c (first s)
                sc (seq c)]
            (if sc
              (cons (first sc) (mapcat-step (rest s) (rest sc)))
              (mapcat-step (rest s) nil)))
          nil)))))

(defn mapcat
  ([f] (comp (map f) cat))
  ([f coll]
   (mapcat-step (map f coll) nil))
  ([f c1 c2]
   (mapcat-step (map f c1 c2) nil))
  ([f c1 c2 c3]
   (mapcat-step (map f c1 c2 c3) nil))
  ([f c1 c2 c3 & colls]
   (mapcat-step (apply map f c1 c2 c3 colls) nil)))
