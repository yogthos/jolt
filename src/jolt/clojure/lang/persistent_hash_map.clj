(ns jolt.lang.persistent-hash-map
  "PersistentHashMap: HAMT implementation.")

(def branch-factor 32)
(def shift-increment 5)

(deftype BitmapIndexedNode [bitmap array])
(deftype PersistentHashMap [count root has-nil? nil-value _meta])

(defn- mask [hash shift]
  (int (bit-and (unsigned-bit-shift-right hash shift) 31)))

(defn- bitpos [hash shift]
  (bit-shift-left 1 (mask hash shift)))

(defn- bit-count [n]
  (let [n (- n (bit-and (unsigned-bit-shift-right n 1) 1431655765))
        n (+ (bit-and n 858993459) (bit-and (unsigned-bit-shift-right n 2) 858993459))
        n (bit-and (+ n (unsigned-bit-shift-right n 4)) 252645135)
        n (+ n (unsigned-bit-shift-right n 8))
        n (+ n (unsigned-bit-shift-right n 16))]
    (int (bit-and n 63))))

(defn- index [bm bit]
  (bit-count (bit-and bm (dec bit))))

(def not-found ::not-found)
(def EMPTY (PersistentHashMap. 0 nil false nil nil))

(defn- bmn-assoc [node shift hash key val added?]
  (let [bit (bitpos hash shift)
        idx (* 2 (index (.-bitmap node) bit))]
    (if (= 0 (bit-and (.-bitmap node) bit))
      (let [n (bit-count (.-bitmap node))
            new-len (* 2 (inc n))
            a (object-array new-len)
            new-bm (bit-or (.-bitmap node) bit)]
        (loop [i 0]
          (if (< i idx)
            (do (aset a i (aget (.-array node) i))
                (aset a (inc i) (aget (.-array node) (inc i)))
                (recur (+ i 2)))))
        (loop [i idx]
          (if (< i (* 2 n))
            (do (aset a (+ i 2) (aget (.-array node) i))
                (aset a (+ i 3) (aget (.-array node) (inc i)))
                (recur (+ i 2))))))
        (aset a idx key)
        (aset a (inc idx) val)
        (aset added? 0 true)
        (BitmapIndexedNode. new-bm a))
      (let [ek (aget (.-array node) idx)]
        (if (identical? ek key)
          (let [a (aclone (.-array node))]
            (aset a (inc idx) val)
            (BitmapIndexedNode. (.-bitmap node) a))
          (let [ev (aget (.-array node) (inc idx))
                a (aclone (.-array node))
                sub (BitmapIndexedNode. 0 (object-array 2))]
            (aset added? 0 true)
            (aset a idx nil)
            (aset a (inc idx)
                  (bmn-assoc (bmn-assoc sub (+ shift shift-increment)
                                        (hash ek) ek ev added?)
                             (+ shift shift-increment) hash key val added?))
            (BitmapIndexedNode. (.-bitmap node a)))))))

(defn- bmn-find [node shift hash key]
  (let [bit (bitpos hash shift)]
    (if (= 0 (bit-and (.-bitmap node) bit))
      not-found
      (let [idx (* 2 (index (.-bitmap node) bit))
            k (aget (.-array node) idx)]
        (if (nil? k)
          (bmn-find (aget (.-array node) (inc idx))
                    (+ shift shift-increment) hash key)
          (if (identical? k key)
            (aget (.-array node) (inc idx))
            not-found))))))

(defn phm-assoc [m key val]
  (if (nil? key)
    (PersistentHashMap.
      (if (.-has-nil? m) (.-count m) (inc (.-count m)))
      (.-root m) true val (.-_meta m))
    (let [added? (object-array 1)
          h (hash key)
          r (if (nil? (.-root m))
              (bmn-assoc (BitmapIndexedNode. 0 (object-array 2)) 0 h key val added?)
              (bmn-assoc (.-root m) 0 h key val added?))]
      (PersistentHashMap.
        (if (aget added? 0) (inc (.-count m)) (.-count m))
        r (.-has-nil? m) (.-nil-value m) (.-_meta m)))))

(defn phm-get
  ([m key] (phm-get m key nil))
  ([m key nf]
   (if (nil? key)
     (if (.-has-nil? m) (.-nil-value m) nf)
     (if (nil? (.-root m))
       nf
       (let [result (bmn-find (.-root m) 0 (hash key) key)]
         (if (identical? result not-found) nf result))))))

(defn phm-contains? [m key]
  (if (nil? key)
    (.-has-nil? m)
    (if (nil? (.-root m))
      false
      (not (identical? (bmn-find (.-root m) 0 (hash key) key) not-found)))))

(defn phm-count [m] (.-count m))

(defn hash-map [& kvs]
  (if (nil? kvs)
    EMPTY
    (loop [m EMPTY pairs (seq kvs)]
      (if (and pairs (seq (rest pairs)))
        (recur (phm-assoc m (first pairs) (first (rest pairs)))
               (rest (rest pairs)))
        m))))
