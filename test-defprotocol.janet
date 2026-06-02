(use ./src/jolt/evaluator)
(use ./src/jolt/types)
(use ./src/jolt/reader)
(use ./src/jolt/api)

(def ctx (init))

# Test simple defprotocol expansion
(def proto-name {:jolt/type :symbol :ns nil :name "IBox"})
(def sig1 @[{:jolt/type :symbol :ns nil :name "setVal"} {:jolt/type :symbol :ns nil :name "_this"} {:jolt/type :symbol :ns nil :name "_v"}])
(def sig2 @[{:jolt/type :symbol :ns nil :name "getVal"} {:jolt/type :symbol :ns nil :name "_this"}])

# Call core-defprotocol directly
(use ./src/jolt/core)
(def expanded (core-defprotocol proto-name sig1 sig2))
(print "expanded: " (string expanded))

# Try to eval it
(def [ok err] (protect (eval-form ctx @{} expanded)))
(if ok
  (do
    (print "eval OK!")
    (let [ns (ctx-find-ns ctx (ctx-current-ns ctx))]
      (printf "IBox: %q\n" (ns-find ns "IBox"))
      (printf "setVal: %q\n" (ns-find ns "setVal"))))
  (printf "eval FAIL: %q\n" err))
