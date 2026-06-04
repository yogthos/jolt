# Jolt REPL
# Read-eval-print loop for Clojure expressions.

(use ./api)
(use ./types)
(use ./phm)
(use ./reader)

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

    # LazySeq — realize the cell chain and print as a list. Capped to avoid
    # hanging on infinite sequences; prints "..." when truncated.
    (and (table? v) (= :jolt/lazy-seq (v :jolt/type)))
    (do
      (push-str buf "(")
      (var cur v)
      (var i 0)
      (var go true)
      (while (and go (< i 1000))
        (let [cell (realize-ls cur)]
          (if (or (nil? cell) (= :jolt/pending cell) (= 0 (length cell)))
            (set go false)
            (do
              (when (> i 0) (push-str buf " "))
              (write-value (in cell 0) buf)
              (++ i)
              (let [rt (in cell 1)]
                (if (nil? rt) (set go false) (set cur (make-lazy-seq rt))))))))
      (when (and go (>= i 1000)) (push-str buf " ..."))
      (push-str buf ")"))

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

    (and (table? v) (= :jolt/regex (v :jolt/type)))
    (do (push-str buf "#\"") (push-str buf (v :source)) (push-str buf "\""))

    (and (table? v) (= :jolt/sorted-map (v :jolt/type)))
    (do
      (push-str buf "{")
      (var first? true)
      (each k (sort (array ;(keys (v :map))))
        (if first? (set first? false) (push-str buf ", "))
        (write-value k buf) (push-str buf " ") (write-value (get (v :map) k) buf))
      (push-str buf "}"))

    (and (table? v) (= :jolt/sorted-set (v :jolt/type)))
    (do
      (push-str buf "#{")
      (var first? true)
      (each x (v :items)
        (if first? (set first? false) (push-str buf " "))
        (write-value x buf))
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
    (and (struct? v) (= :jolt/char (get v :jolt/type)))
    (do (push-str buf "\\")
        (push-str buf (case (v :ch)
                        10 "newline" 32 "space" 9 "tab" 13 "return"
                        12 "formfeed" 8 "backspace" 0 "nul"
                        (string/from-bytes (v :ch)))))
    (and (struct? v) (= :symbol (get v :jolt/type)))
    (let [ns (get v :ns) name (get v :name)]
      (if ns
        (push-str buf (string ns "/" name))
        (push-str buf name)))
    (and (table? v) (= :jolt/var (v :jolt/type)))
    (push-str buf (string "#'" (ctx-current-ns ctx) "/" (var-name v)))
    (or (tuple? v) (array? v) (struct? v) (table? v))
    (write-collection v buf)
    true (push-str buf (string v)))))

(defn print-value [v]
  (def buf @"")
  (write-value v buf)
  (print (string buf)))

(defn main [&]
  (print "Jolt — Clojure on Janet")
  (print "Type (exit) to quit.\n")

  (var running true)
  (var pending "")   # accumulates a form split across multiple input lines
  (while running
    (let [prompt (if (= pending "") (string (ctx-current-ns ctx) "=> ") "  #_=> ")
          line (read-line prompt)]
      (cond
        (nil? line) (set running false)
        (let [input (if (= pending "") line (string pending "\n" line))
              trimmed (string/trim input)]
          (cond
            (= trimmed "(exit)") (set running false)
            (= trimmed "") (set pending "")
            # Try to parse the accumulated input; if it's an incomplete form
            # (unterminated list/vector/map/string), keep reading more lines.
            (let [parsed (protect (parse-string input))]
              (if (and (= (parsed 0) false)
                       (string/find "nterminated" (string (parsed 1))))
                (set pending input)
                (do
                  (set pending "")
                  (try
                    (print-value (eval-string ctx input))
                    ([err] (eprint "Error: " err))))))))))))
