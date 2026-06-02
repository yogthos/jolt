(use ./src/jolt/evaluator)
(use ./src/jolt/types)
(use ./src/jolt/reader)
(use ./src/jolt/api)

(def ctx (init))
(eval-form ctx @{} (parse-string "(ns sci.lang)"))
(eval-form ctx @{} (parse-string "(definterface IVar)"))

# Resolve sci.lang/IVar by evaluating as a qualified symbol
(def sym (parse-string "sci.lang/IVar"))
(printf "sym: %q\n" sym)
(try
  (def v (eval-form ctx @{} sym))
  (printf "resolved: %q\n" v)
  ([err] (printf "error: %q\n" err)))
