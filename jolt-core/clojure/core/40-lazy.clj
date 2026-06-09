;; clojure.core — lazy tier. Canonical CLJS-based lazy seq fns.
;; Loaded after 30-macros.clj, so lazy-seq macro is available.
;;
;; Each fn ported from CLJS core.cljs, stripped of chunked-seq branches.

;; --- distinct --- (transducer + lazy collection arity; value-based dedup)
(defn distinct
  ([]
   (fn [rf]
     (let [seen (volatile! #{})]
       (fn ([] (rf)) ([result] (rf result))
         ([result input]
          (if (contains? @seen input)
            result
            (do (vswap! seen conj input) (rf result input))))))))
  ([coll]
   (let [step (fn step [xs seen]
                (lazy-seq
                  ((fn [[f :as xs] seen]
                     (when-let [s (seq xs)]
                       (if (contains? seen f)
                         (recur (rest s) seen)
                         (cons f (step (rest s) (conj seen f))))))
                    xs seen)))]
     (step coll #{}))))


;; --- keep ---
(defn keep
  ([f]
   (fn [rf]
     (fn ([] (rf)) ([result] (rf result))
       ([result input]
        (let [v (f input)]
          (if (nil? v) result (rf result v)))))))
  ([f coll]
   (lazy-seq
    (when-let [s (seq coll)]
      (let [x (f (first s))]
        (if (nil? x)
          (keep f (rest s))
          (cons x (keep f (rest s)))))))))

;; --- keep-indexed ---
(defn keep-indexed
  ([f]
   (fn [rf]
     (let [ia (volatile! -1)]
       (fn ([] (rf)) ([result] (rf result))
         ([result input]
          (let [i (vswap! ia inc)
                v (f i input)]
            (if (nil? v) result (rf result v))))))))
  ([f coll]
   (letfn [(keepi [idx coll]
             (lazy-seq
               (when-let [s (seq coll)]
                 (let [x (f idx (first s))]
                   (if (nil? x)
                     (keepi (inc idx) (rest s))
                     (cons x (keepi (inc idx) (rest s))))))))]
     (keepi 0 coll))))

;; --- map-indexed ---
(defn map-indexed
  ([f]
   (fn [rf]
     (let [i (volatile! -1)]
       (fn ([] (rf)) ([result] (rf result))
         ([result input] (rf result (f (vswap! i inc) input)))))))
  ([f coll]
   (letfn [(mapi [idx coll]
             (lazy-seq
               (when-let [s (seq coll)]
                 (cons (f idx (first s)) (mapi (inc idx) (rest s))))))]
     (mapi 0 coll))))

;; --- cycle ---
(defn cycle [coll]
  (if-let [vals (seq coll)]
    (let [n (count vals)]
      (letfn [(cstep [i]
                (lazy-seq
                  (cons (nth vals (mod i n)) (cstep (inc i)))))]
        (cstep 0)))
    ()))

;; repeatedly stays in the Janet seed for now (core-repeatedly): the canonical CLJ
;; version doesn't validate args, so (first (repeatedly non-fn)) / (repeatedly \a +)
;; don't throw like the stricter Janet version (repeatedly.cljc throw cases).
;; Ported separately once the non-fn / non-number-count throws are matched.

;; --- repeat ---
(defn repeat
  ([x] (lazy-seq (cons x (repeat x))))
  ([n x] (take n (repeat x))))

;; --- iterate ---
(defn iterate [f x]
  (lazy-seq (cons x (iterate f (f x)))))


;; partition-all stays in the Janet seed for now (core-partition-all): it already
;; has the transducer + collection arities (jolt-cru), and a CLJ port realizes a
;; different (non-minimal) element count via take/drop than the Janet one,
;; tripping the §6.3 laziness counters + a suite file. Ported separately.
