; Jolt Standard Library: clojure.java.io
; File I/O using Janet's built-in file functions.

(defn file
  ([path] (string path))
  ([parent child] (string parent "/" child)))

(defn as-file [x] (if (string? x) x (str x)))

(defn as-url [x] (str x))

(defn delete-file [f &opt silently]
  (try (os/rm f) true
    ([err] (if silently false (error err)))))

(defn make-parents [f]
  (let [parent (string/replace f "/[^/]+$" "")]
    (when (not= parent f)
      (os/mkdir parent))))

(defn reader [f]
  (file/open f :r))

(defn writer [f]
  (file/open f :w))

(defn input-stream [f]
  (file/open f :r))

(defn output-stream [f]
  (file/open f :w))

(defn resource [path] (slurp path))

(defn copy [input output]
  (let [content (if (string? input) (slurp input) (file/read input :all))]
    (if (string? output) (spit output content) (file/write output content))))
