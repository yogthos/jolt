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

(defn print-value [v]
  (if (nil? v)
    (print "nil")
    (if (and (table? v) (= :jolt/var (v :jolt/type)))
      (printf "#'%s/%s" (ctx-current-ns ctx) ((var-name v) :name))
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
