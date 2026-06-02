(ns jolt.lang.persistent-hash-map
  "PersistentHashMap using simple array-based implementation.")

(deftype PersistentHashMap [count root has-nil? nil-value _meta])

(def EMPTY (PersistentHashMap. 0 nil false nil nil))

(defn- mask [hash shift]
  (mod (abs (int hash)) 32))

(defn- find-key-index [arr key]
  (let [len (alength arr)]
    (loop [i 0]
      (if (< i len)
        (if (identical? (aget arr i) key)
          i
          (recur (+ i 2)))
        -1))))

(defn- node-assoc [arr h key val added?]
  (let [idx (find-key-index arr key)]
    (if (= idx -1)
      ;; Insert — create new array with +2 slots
      (let [old-len (alength arr)
            new-arr (object-array (+ old-len 2))]
        (loop [i 0]
          (if (< i old-len)
            (do (aset new-arr i (aget arr i))
                (recur (inc i)))))
        (aset new-arr old-len key)
        (aset new-arr (inc old-len) val)
        (aset added? 0 true)
        new-arr)
      ;; Replace — clone and update
      (let [new-arr (aclone arr)]
        (aset new-arr (inc idx) val)
        new-arr))))

(defn- node-find [arr key]
  (let [idx (find-key-index arr key)]
    (if (= idx -1)
      nil
      (aget arr (inc idx)))))

(defn phm-assoc [m key val]
  (if (nil? key)
    (PersistentHashMap.
      (if (.-has-nil? m) (.-count m) (inc (.-count m)))
      (.-root m) true val (.-_meta m))
    (let [added? (object-array 1)
          root (.-root m)
          new-arr (node-assoc (if (nil? root) (object-array 0) root)
                              (hash key) key val added?)]
      (PersistentHashMap.
        (if (aget added? 0) (inc (.-count m)) (.-count m))
        new-arr (.-has-nil? m) (.-nil-value m) (.-_meta m)))))

(defn phm-get
  ([m key] (phm-get m key nil))
  ([m key not-found]
   (if (nil? key)
     (if (.-has-nil? m) (.-nil-value m) not-found)
     (let [root (.-root m)]
       (if (nil? root)
         not-found
         (let [result (node-find root key)]
           (if (nil? result) not-found result)))))))

(defn phm-contains? [m key]
  (not (nil? (phm-get m key ::sentinel))))

(defn phm-count [m] (.-count m))

(defn hash-map [& kvs]
  (if (nil? kvs)
    EMPTY
    (loop [m EMPTY pairs (seq kvs)]
      (if (and pairs (seq (rest pairs)))
        (recur (phm-assoc m (first pairs) (first (rest pairs)))
               (rest (rest pairs)))
        m))))
