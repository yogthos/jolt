; Jolt Standard Library: clojure.zip
; Functional zipper for tree navigation and editing.

(defn zipper
  [branch? children make-node root]
  (let [z {:l [] :r [] :node root :pnodes [] :ppath nil :changed? false}]
    (if (branch? root)
      (let [chs (children root)]
        (assoc z :l (vec (rest chs)) :node (first chs) :pnodes (conj (:pnodes z) root)))
      z)))

(defn node [z] (:node z))
(defn branch? [z] (and z (not (nil? (:node z)))))

(defn make-node [z node children]
  (let [m (assoc z :node node :changed? true)]
    (if children (assoc m :l (vec children)) m)))

(defn path [z] (:pnodes z))

(defn left [z]
  (let [ls (:l z)]
    (if (and (branch? z) (seq ls))
      (assoc z :l (vec (rest ls)) :node (first ls)) nil)))

(defn right [z]
  (if (and (branch? z) (seq (:r z)))
    (assoc z :l (conj (:l z) (:node z)) :node (first (:r z)) :r (vec (rest (:r z)))) nil))

(defn up [z]
  (if (seq (path z))
    (let [pn (peek (path z))]
      (assoc z :l nil :r (vec (concat (conj (:l z) (:node z)) (:r z))) :node pn :pnodes (pop (path z)))) nil))

(defn down [z]
  (when (branch? z)
    (let [chs (children z)]
      (when (seq chs)
        (assoc z :node (first chs) :l [] :r (vec (rest chs)) :pnodes (conj (path z) (:node z)))))))

(defn leftmost [z]
  (let [p (up z)] (if p (down p) z)))

(defn rightmost [z]
  (let [p (up z)]
    (if p
      (let [chs (children p)]
        (assoc z :node (last chs) :l (vec (butlast chs)) :r [] :pnodes (conj (pop (path z)) (:node p)))) z)))

(defn next [z]
  (if (= :end z) z
    (or (and (branch? z) (down z))
        (right z)
        (loop [p z]
          (if (up p)
            (or (right (up p)) (recur (up p)))
            (assoc z :node :end))))))

(defn prev [z]
  (if-let [l (left z)]
    (loop [l l]
      (if-let [d (and (branch? l) (down l))]
        (recur (rightmost d)) l)) (up z)))

(defn end? [z] (= :end (:node z)))

(defn remove [z]
  (if-let [p (up z)]
    (let [chs (children p)
          new-chs (remove #{(:node z)} chs)]
      (up (make-node p (:node p) new-chs))) (assoc z :node nil)))

(defn replace [z node]
  (assoc z :node node :changed? true))

(defn edit [z f & args]
  (replace z (apply f (:node z) args)))

(defn insert-left [z item]
  (assoc z :l (conj (:l z) item)))

(defn insert-right [z item]
  (assoc z :r (into [item] (:r z))))

(defn insert-child [z item]
  (assoc z :l (into [item] (:l z))))

(defn append-child [z item]
  (assoc z :l (conj (vec (:l z)) item)))

(defn root [z]
  (if (seq (path z)) (recur (up z)) (:node z)))

(defn vector-zip [root]
  (zipper vector? seq (fn [node children] (vec children)) root))

(defn seq-zip [root]
  (zipper seq? identity (fn [node children] (with-meta children (meta node))) root))
