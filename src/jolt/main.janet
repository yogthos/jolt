# Jolt REPL
# Read-eval-print loop for Clojure expressions.

(use ./api)
(use ./types)

(def ctx (init))

(defn read-line [prompt]
  (prin prompt)
  (flush)
  (let [line (file/read stdin :line)]
    (if line (string/trim line) nil)))

# Forward declaration for mutual recursion
(var print-value nil)

(defn- print-collection [v]
  (cond
    (tuple? v)
    (do
      (prin "[")
      (var i 0)
      (let [n (length v)]
        (while (< i n)
          (print-value (in v i))
          (when (< (+ i 1) n) (prin " "))
          (++ i)))
      (prin "]"))

    (array? v)
    (do
      (prin "(")
      (var i 0)
      (let [n (length v)]
        (while (< i n)
          (print-value (in v i))
          (when (< (+ i 1) n) (prin " "))
          (++ i)))
      (prin ")"))

    (and (table? v) (= :jolt/set (v :jolt/type)))
    (do
      (prin "#{")
      (var first? true)
      (each k (keys (v :phm))
        (when (not= k :jolt/deftype)
          (if first? (set first? false) (prin " "))
          (print-value k)))
      (prin "}"))

    (and (table? v) (get v :jolt/deftype))
    (do
      (prin "{")
      (var first? true)
      (each [k val] (pairs v)
        (when (and (not= k :jolt/deftype) (not= k :cnt) (not= k :buckets) (not= k :_meta)
                   (not= k :jolt/type) (not= k :phm))
          (if first? (set first? false) (prin " "))
          (print-value k)
          (prin " ")
          (print-value val)))
      (prin "}"))

    (struct? v)
    (do
      (prin "{")
      (var first? true)
      (each [k val] (pairs v)
        (if first? (set first? false) (prin " "))
        (print-value k)
        (prin " ")
        (print-value val))
      (prin "}"))

    (table? v)
    (do
      (prin "{")
      (var first? true)
      (each [k val] (pairs v)
        (when (not= k :jolt/type)
          (if first? (set first? false) (prin " "))
          (print-value k)
          (prin " ")
          (print-value val)))
      (prin "}"))))

(set print-value (fn [v]
  (cond
    (nil? v) (print "nil")
    (= true v) (print "true")
    (= false v) (print "false")
    (number? v) (print v)
    (string? v) (print v)
    (keyword? v) (prin ":") (print (string v))
    (and (table? v) (= :jolt/var (v :jolt/type)))
    (printf "#'%s/%s" (ctx-current-ns ctx) ((var-name v) :name))
    (or (tuple? v) (array? v) (struct? v) (table? v))
    (print-collection v)
    (print v))))

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
