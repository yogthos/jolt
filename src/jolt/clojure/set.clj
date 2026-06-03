; Jolt Standard Library: clojure.set
; Set operations. Note: no & rest arities (evaluator limitation).

(defn union
  ([s1] s1)
  ([s1 s2] (reduce conj s2 s1)))

(defn intersection
  ([s1] s1)
  ([s1 s2]
   (reduce (fn [acc item] (if (contains? s2 item) acc (disj acc item))) s1 s1)))

(defn difference
  ([s1] s1)
  ([s1 s2] (reduce disj s1 s2)))

(defn select
  [pred s]
  (reduce (fn [acc item] (if (pred item) acc (disj acc item))) s s))

(defn project
  [xrel ks]
  (set (map #(select-keys % ks) xrel)))

(defn rename-keys
  [map kmap]
  (reduce (fn [m [old new]] (if (contains? m old) (assoc m new (get m old) old nil) m)) map kmap))

(defn map-invert
  [m]
  (reduce (fn [acc [k v]] (assoc acc v k)) {} m))

(defn rename
  [xrel kmap]
  (set (map (fn [m]
    (reduce (fn [acc [old new]] (if (contains? m old) (assoc acc new (get m old)) acc))
            (apply dissoc m (keys kmap)) kmap)) xrel)))

(defn index
  [xrel ks]
  (reduce (fn [m x] (let [ik (select-keys x ks)] (assoc m ik (conj (get m ik #{}) x)))) {} xrel))

(defn subset?
  [set1 set2]
  (and (<= (count set1) (count set2))
       (every? #(contains? set2 %) set1)))

(defn superset?
  [set1 set2]
  (and (>= (count set1) (count set2))
       (every? #(contains? set1 %) set2)))
