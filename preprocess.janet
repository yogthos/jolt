# Preprocess a cljc file: resolve #?(:clj ...) and #?@(:clj ...) reader conditionals
# at read time. Output a plain .clj file that Jolt can parse without reader conditionals.

(use ./src/jolt/reader)

(defn preprocess [filepath]
  (def src (slurp filepath))
  (var s src)
  (var out @[])
  (var count 0)
  (while (> (length (string/trim s)) 0)
    (def [form rest] (parse-next s))
    (set s rest)
    (++ count)
    (if (nil? form)
      nil
      (array/push out (string form))))
  (string/join out "\n"))

(def filepath (if (> (length (dyn :args @[])) 0) (in (dyn :args) 0) "/Users/yogthos/src/sci/src/sci/impl/utils.cljc"))
(print (preprocess filepath))
