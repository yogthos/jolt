(use ../src/jolt/evaluator)
(use ../src/jolt/types)
(use ../src/jolt/reader)

# Helper: create a Jolt symbol
(defn sym [name]
  (let [slash (string/find "/" name)]
    (if slash
      {:jolt/type :symbol :ns (string/slice name 0 slash)
       :name (string/slice name (+ slash 1))}
      {:jolt/type :symbol :ns nil :name name})))

# Helper: parse and eval
(defn eval-str [s]
  (let [ctx (make-ctx)
        form (parse-string s)]
    (eval-form ctx @{} form)))

(print "1: literals...")
(assert (= 42 (eval-str "42")) "integer")
(assert (= "hello" (eval-str "\"hello\"")) "string")
(assert (= true (eval-str "true")) "true")
(assert (= false (eval-str "false")) "false")
(assert (= nil (eval-str "nil")) "nil")
(print "  passed")

(print "2: quote...")
(assert (deep= (sym "x") (eval-str "'x")) "quote returns symbol")
(assert (deep= @[1 2 3] (eval-str "'(1 2 3)")) "quote list")
(print "  passed")

(print "3: do...")
(assert (= 2 (eval-str "(do 1 2)")) "do returns last")
(print "  passed")

(print "4: if...")
(assert (= 1 (eval-str "(if true 1 2)")) "if true")
(assert (= 2 (eval-str "(if false 1 2)")) "if false")
(assert (= :b (eval-str "(if nil :a :b)")) "if nil = false")
(assert (= nil (eval-str "(if false 1)")) "if with no else")
(print "  passed")

(print "5: def...")
(assert (= 42 (eval-str "(do (def x 42) x)")) "def in do")
(print "  passed")

(print "6: fn*...")
(let [f (eval-str "(fn* [x] (inc x))")]
  (assert (function? f) "fn* returns function")
  (assert (= 42 (f 41)) "fn* fn works"))
# nested function
(let [f (eval-str "(fn* [x] (inc (inc x)))")]
  (assert (= 43 (f 41)) "nested inc"))
(print "  passed")

(print "7: let*...")
(assert (= 2 (eval-str "(let* [x 1 y 2] y)")) "let* binds")
(assert (= 3 (eval-str "(let* [x 1] (inc (inc x)))")) "let* with expr")
(print "  passed")

(print "8: loop*/recur...")
(assert (= 5 (eval-str "(loop* [x 0] (if (< x 5) (recur (inc x)) x))"))
        "loop counts up")
(assert (= 10 (eval-str "(loop* [i 0 acc 0] (if (< i 5) (recur (inc i) (+ acc i)) acc))"))
        "loop with multiple bindings")
(print "  passed")

(print "9: recur in fn*...")
(let [countdown (eval-str "(fn* [n] (if (< n 1) 0 (recur (dec n))))")]
  (assert (= 0 (countdown 5)) "recur in fn"))
(print "  passed")

(print "\nAll evaluator tests passed!")
