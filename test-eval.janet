(use ./src/jolt/evaluator)
(use ./src/jolt/types)
(use ./src/jolt/reader)
(use ./src/jolt/api)

(def ctx (init))

(defn load-all []
  (each fp ["/Users/yogthos/src/sci/src/sci/impl/macros.cljc"
            "/Users/yogthos/src/sci/src/sci/impl/protocols.cljc"
            "/Users/yogthos/src/sci/src/sci/impl/utils.cljc"
            "/Users/yogthos/src/sci/src/sci/impl/types.cljc"
            "/Users/yogthos/src/sci/src/sci/impl/unrestrict.cljc"]
    (def src (slurp fp))
    (var s src)
    (while (> (length (string/trim s)) 0)
      (def [f r] (parse-next s)) (set s r)
      (if (not (nil? f)) (protect (eval-form ctx @{} f)))))
  (def vs (slurp "/Users/yogthos/src/sci/src/sci/impl/vars.cljc"))
  (var s vs) (var c 0)
  (while (and (> (length (string/trim s)) 0) (< c 27))
    (def [f r] (parse-next s)) (set s r) (++ c)
    (if (not (nil? f)) (protect (eval-form ctx @{} f))))
  (each fp ["/Users/yogthos/src/sci/src/sci/lang.cljc"
            "/Users/yogthos/src/sci/src/sci/core.cljc"]
    (def src (slurp fp))
    (var s src)
    (while (> (length (string/trim s)) 0)
      (def [f r] (parse-next s)) (set s r)
      (if (not (nil? f)) (protect (eval-form ctx @{} f))))))

(load-all)

(print "=== Testing eval-string ===")

# Call sci.core/eval-string via our own eval
(def src "(do (require (quote [sci.core :as sci])) (sci/eval-string (sci/init) (str (+ 1 2))))")
(printf "eval: %s\n" src)
(try
  (def result (eval-form ctx @{} (parse-string src)))
  (printf "result: %q\n" result)
  ([err] (printf "FAIL: %q\n" err)))
