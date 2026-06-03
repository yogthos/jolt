# Jolt REPL
# Read-eval-print loop for Clojure expressions.

(use ./api)
(use ./types)

(def ctx (init))
(ctx-set-current-ns ctx "user")

(defn read-line [prompt]
  (prin prompt)
  (flush)
  (let [line (file/read stdin :line)]
    (if line (string/trim line) nil)))

# Forward declaration for mutual recursion
(var write-value nil)

(defn- push-str [buf s]
  (buffer/push-string buf s))

(defn- write-collection [v buf]
  (cond
    (tuple? v)
    (do
      (push-str buf "[")
      (var i 0)
      (let [n (length v)]
        (while (< i n)
          (write-value (in v i) buf)
          (when (< (+ i 1) n) (push-str buf " "))
          (++ i)))
      (push-str buf "]"))

    (array? v)
    (do
      (push-str buf "(")
      (var i 0)
      (let [n (length v)]
        (while (< i n)
          (write-value (in v i) buf)
          (when (< (+ i 1) n) (push-str buf " "))
          (++ i)))
      (push-str buf ")"))

    (and (table? v) (= :jolt/set (v :jolt/type)))
    (do
      (push-str buf "#{")
      (var first? true)
      (each k (keys (v :phm))
        (when (not= k :jolt/deftype)
          (if first? (set first? false) (push-str buf " "))
          (write-value k buf)))
      (push-str buf "}"))

    (and (table? v) (get v :jolt/deftype))
    (do
      (push-str buf "{")
      (var first? true)
      (each [k val] (pairs v)
        (when (and (not= k :jolt/deftype) (not= k :cnt) (not= k :buckets)
                   (not= k :_meta) (not= k :jolt/type) (not= k :phm))
          (if first? (set first? false) (push-str buf " "))
          (write-value k buf)
          (push-str buf " ")
          (write-value val buf)))
      (push-str buf "}"))

    (struct? v)
    (do
      (push-str buf "{")
      (var first? true)
      (each [k val] (pairs v)
        (if first? (set first? false) (push-str buf " "))
        (write-value k buf)
        (push-str buf " ")
        (write-value val buf))
      (push-str buf "}"))

    (table? v)
    (do
      (push-str buf "{")
      (var first? true)
      (each [k val] (pairs v)
        (when (not= k :jolt/type)
          (if first? (set first? false) (push-str buf " "))
          (write-value k buf)
          (push-str buf " ")
          (write-value val buf)))
      (push-str buf "}"))))

(set write-value (fn [v buf]
  (cond
    (nil? v) (push-str buf "nil")
    (= true v) (push-str buf "true")
    (= false v) (push-str buf "false")
    (number? v) (push-str buf (string v))
    (string? v) (push-str buf v)
    (keyword? v) (do (push-str buf ":") (push-str buf (string v)))
    (and (struct? v) (= :symbol (get v :jolt/type)))
    (let [ns (get v :ns) name (get v :name)]
      (if ns
        (push-str buf (string ns "/" name))
        (push-str buf name)))
    (and (table? v) (= :jolt/var (v :jolt/type)))
    (push-str buf (string "#'" (ctx-current-ns ctx) "/" ((var-name v) :name)))
    (or (tuple? v) (array? v) (struct? v) (table? v))
    (write-collection v buf)
    (push-str buf (string v)))))

(defn print-value [v]
  (def buf @"")
  (write-value v buf)
  (print (string buf)))

(defn main [&]
  (print "Jolt — Clojure on Janet")
  (print "Type (exit) to quit.\n")

  (var running true)
  (while running
    (let [line (read-line (string (ctx-current-ns ctx) "=> "))]
      (if (nil? line) (set running false)
        (if (= line "(exit)") (set running false)
          (if (not (= "" line))
            (try
              (print-value (eval-string ctx line))
              ([err]
               (eprint "Error: " err)))))))))
