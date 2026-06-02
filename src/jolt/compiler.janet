# Jolt Compiler
# Source-to-source: Clojure forms → Janet source
# Two-phase: analyze-form (classify) → emit-ast (generate)

(def- core-renames
  @{"+" "core-+"
    "-" "core--"
    "*" "core-*"
    "/" "core-/"
    "inc" "core-inc"
    "dec" "core-dec"
    "=" "core-="
    "not=" "core-not="
    "<" "core-<"
    ">" "core->"
    "<=" "core-<="
    ">=" "core->="
    "nil?" "core-nil?"
    "not" "core-not"
    "some?" "core-some?"
    "string?" "core-string?"
    "number?" "core-number?"
    "keyword?" "core-keyword?"
    "symbol?" "core-symbol?"
    "vector?" "core-vector?"
    "map?" "core-map?"
    "seq?" "core-seq?"
    "coll?" "core-coll?"
    "first" "core-first"
    "rest" "core-rest"
    "next" "core-next"
    "cons" "core-cons"
    "conj" "core-conj"
    "assoc" "core-assoc"
    "dissoc" "core-dissoc"
    "get" "core-get"
    "get-in" "core-get-in"
    "contains?" "core-contains?"
    "count" "core-count"
    "empty?" "core-empty?"
    "every?" "core-every?"
    "seq" "core-seq"
    "vec" "core-vec"
    "map" "core-map"
    "filter" "core-filter"
    "remove" "core-remove"
    "reduce" "core-reduce"
    "apply" "core-apply"
    "str" "core-str"
    "prn" "core-prn"
    "pr-str" "core-pr-str"
    "println" "core-println"
    "print" "core-print"
    "identity" "core-identity"
    "comp" "core-comp"
    "partial" "core-partial"
    "complement" "core-complement"
    "constantly" "core-constantly"
    "memoize" "core-memoize"
    "some" "core-some"
    "range" "core-range"
    "take" "core-take"
    "drop" "core-drop"
    "take-while" "core-take-while"
    "drop-while" "core-drop-while"
    "nth" "core-nth"
    "reverse" "core-reverse"
    "into" "core-into"
    "merge" "core-merge"
    "merge-with" "core-merge-with"
    "keys" "core-keys"
    "vals" "core-vals"
    "zipmap" "core-zipmap"
    "select-keys" "core-select-keys"
    "max" "core-max"
    "min" "core-min"
    "odd?" "core-odd?"
    "even?" "core-even?"
    "zero?" "core-zero?"
    "pos?" "core-pos?"
    "neg?" "core-neg?"
    "true?" "core-true?"
    "false?" "core-false?"
    "identical?" "core-identical?"
    "quot" "core-quot"
    "rem" "core-rem"
    "mod" "core-mod"})

(defn- literal?
  [form]
  (or (nil? form) (= true form) (= false form)
      (number? form) (string? form) (keyword? form) (bytes? form) (buffer? form)))

(defn- special-form?
  [name]
  (or (= name "quote") (= name "syntax-quote") (= name "do")
      (= name "if") (= name "def") (= name "defmacro") (= name "fn*")
      (= name "let*") (= name "loop*") (= name "recur") (= name "throw")
      (= name "try") (= name "set!") (= name "var") (= name ".")
      (= name "new") (= name "deftype") (= name "instance?")
      (= name "defmulti") (= name "defmethod") (= name "locking")))

# ============================================================
# Analyzer
# ============================================================

(defn analyze-form
  [form bindings]
  (cond
    (literal? form)
    {:op :const :val form}

    (and (struct? form) (= :symbol (form :jolt/type)))
    (let [name (form :name)
          ns (form :ns)]
      (if ns
        {:op :qualified-symbol :ns ns :name name}
        (if (get bindings name)
          {:op :local :name name}
          (if (and (not (special-form? name)) (get core-renames name))
            {:op :core-symbol :name name :janet-name (get core-renames name)}
            {:op :symbol :name name}))))

    (array? form)
    (let [first-form (first form)
          head-name (if (and (struct? first-form) (= :symbol (first-form :jolt/type)))
                     (first-form :name)
                     nil)]
      (if head-name
        (match head-name
          "quote" {:op :quote :expr (in form 1)}
          "do" (let [all-statements (array/slice form 1)
                     n (length all-statements)
                     analyzed (map |(analyze-form $ bindings) all-statements)]
                 {:op :do
                  :statements (array/slice analyzed 0 (- n 1))
                  :ret (in analyzed (- n 1))})
          "if" {:op :if
                :test (analyze-form (in form 1) bindings)
                :then (analyze-form (in form 2) bindings)
                :else (if (> (length form) 3)
                       (analyze-form (in form 3) bindings)
                       {:op :const :val nil})}
          "def" {:op :def
                 :name (in form 1)
                 :init (analyze-form (in form 2) bindings)}
          "fn*" (let [params (in form 1)
                      body-bindings (do
                                      (var bb @{})
                                      (loop [[k v] :pairs bindings] (put bb k v))
                                      (each p params
                                        (put bb (if (struct? p) (p :name) p) :jolt/local))
                                      bb)
                      body-exprs (tuple/slice form 2)
                      analyzed-body (map |(analyze-form $ body-bindings) body-exprs)
                      n-body (length analyzed-body)]
                  {:op :fn :params params
                   :body (if (> n-body 1)
                           {:op :do
                            :statements (array/slice analyzed-body 0 (- n-body 1))
                            :ret (last analyzed-body)}
                           (first analyzed-body))})
          "let*" (let [bind-vec (in form 1)
                       body-exprs (tuple/slice form 2)
                       binding-pairs (do
                                       (var pairs @[])
                                       (var i 0)
                                       (let [n (length bind-vec)]
                                         (while (< i n)
                                           (let [sym-s (in bind-vec i)
                                                 name (if (struct? sym-s) (sym-s :name) sym-s)
                                                 val-form (if (< (+ i 1) n) (in bind-vec (+ i 1)) nil)
                                                 val-ast (if val-form (analyze-form val-form bindings) {:op :const :val nil})]
                                             (array/push pairs {:name name :init val-ast})
                                             (+= i 2))))
                                       pairs)
                       body-bindings (do
                                       (var bb @{})
                                       (loop [[k v] :pairs bindings] (put bb k v))
                                       (each bp binding-pairs
                                         (put bb (bp :name) :jolt/local))
                                       bb)
                       analyzed-body (map |(analyze-form $ body-bindings) body-exprs)
                       n-body (length analyzed-body)]
                   {:op :let
                    :binding-pairs binding-pairs
                    :body (if (> n-body 1)
                            {:op :do
                             :statements (array/slice analyzed-body 0 (- n-body 1))
                             :ret (last analyzed-body)}
                            (first analyzed-body))})
          (let [f-ast (analyze-form first-form bindings)
                args (map |(analyze-form $ bindings) (tuple/slice form 1))]
            {:op :invoke :fn f-ast :args args}))
        (let [f-ast (analyze-form first-form bindings)
              args (map |(analyze-form $ bindings) (tuple/slice form 1))]
          {:op :invoke :fn f-ast :args args})))

    (tuple? form)
    (let [items (map |(analyze-form $ bindings) form)]
      {:op :vector :items items})

    (struct? form)
    {:op :map :form form}

    {:op :const :val form}))

# ============================================================
# Emitter — AST → Janet source string
# ============================================================

(var emit-ast nil)

(defn- emit-const-str
  [val buf]
  (cond
    (nil? val) (buffer/push buf "nil")
    (= true val) (buffer/push buf "true")
    (= false val) (buffer/push buf "false")
    (string? val) (do (buffer/push buf "\"") (buffer/push buf val) (buffer/push buf "\""))
    (keyword? val) (do (buffer/push buf ":") (buffer/push buf (string val)))
    (buffer/push buf (string val))))

(defn- emit-do-str [statements ret buf]
  (buffer/push buf "(do ")
  (var i 0)
  (let [n (length statements)]
    (while (< i n)
      (emit-ast (in statements i) buf)
      (buffer/push buf " ")
      (++ i)))
  (when ret (emit-ast ret buf))
  (buffer/push buf ")"))

(defn- emit-if-str [test then else buf]
  (buffer/push buf "(if ")
  (emit-ast test buf) (buffer/push buf " ")
  (emit-ast then buf)
  (when else (buffer/push buf " ") (emit-ast else buf))
  (buffer/push buf ")"))

(defn- emit-def-str [name-sym init buf]
  (buffer/push buf "(def ") (buffer/push buf (name-sym :name))
  (buffer/push buf " ") (emit-ast init buf) (buffer/push buf ")"))

(defn- emit-fn-str [params body buf]
  (buffer/push buf "(fn [")
  (var i 0)
  (let [n (length params)]
    (while (< i n)
      (let [p (in params i)]
        (buffer/push buf (if (struct? p) (p :name) (string p))))
      (when (< (+ i 1) n) (buffer/push buf " "))
      (++ i)))
  (buffer/push buf "] ") (emit-ast body buf) (buffer/push buf ")"))

(defn- emit-let-str [binding-pairs body buf]
  (buffer/push buf "(let [")
  (var i 0)
  (let [n (length binding-pairs)]
    (while (< i n)
      (let [bp (in binding-pairs i)]
        (buffer/push buf (bp :name)) (buffer/push buf " ")
        (emit-ast (bp :init) buf)
        (when (< (+ i 1) n) (buffer/push buf " ")))
      (++ i)))
  (buffer/push buf "] ") (emit-ast body buf) (buffer/push buf ")"))

(defn- emit-invoke-str [f-ast args buf]
  (buffer/push buf "(") (emit-ast f-ast buf)
  (each arg args (buffer/push buf " ") (emit-ast arg buf))
  (buffer/push buf ")"))

(defn- emit-symbol-str [name buf] (buffer/push buf name))
(defn- emit-local-str [name buf] (buffer/push buf name))
(defn- emit-core-symbol-str [janet-name buf] (buffer/push buf janet-name))

(defn- emit-qualified-symbol-str [ns name buf]
  (buffer/push buf "(ns-get \"") (buffer/push buf ns)
  (buffer/push buf "\" \"") (buffer/push buf name) (buffer/push buf "\")"))

(defn- emit-vector-str [items buf]
  (buffer/push buf "[")
  (var i 0)
  (let [n (length items)]
    (while (< i n)
      (emit-ast (in items i) buf)
      (when (< (+ i 1) n) (buffer/push buf " "))
      (++ i)))
  (buffer/push buf "]"))

(defn- emit-map-str [form buf] (buffer/push buf (string form)))

(defn- emit-quote-str [expr buf]
  (buffer/push buf "'") (emit-ast (analyze-form expr @{}) buf))

(set emit-ast
  (fn [ast buf]
    (match (ast :op)
      :const (emit-const-str (ast :val) buf)
      :symbol (emit-symbol-str (ast :name) buf)
      :local (emit-local-str (ast :name) buf)
      :core-symbol (emit-core-symbol-str (ast :janet-name) buf)
      :qualified-symbol (emit-qualified-symbol-str (ast :ns) (ast :name) buf)
      :do (emit-do-str (ast :statements) (ast :ret) buf)
      :if (emit-if-str (ast :test) (ast :then) (ast :else) buf)
      :def (emit-def-str (ast :name) (ast :init) buf)
      :fn (emit-fn-str (ast :params) (ast :body) buf)
      :let (emit-let-str (ast :binding-pairs) (ast :body) buf)
      :invoke (emit-invoke-str (ast :fn) (ast :args) buf)
      :vector (emit-vector-str (ast :items) buf)
      :map (emit-map-str (ast :form) buf)
      :quote (emit-quote-str (ast :expr) buf)
      (buffer/push buf (string "/* unhandled op: " (ast :op) " */")))))

# ============================================================
# Public API
# ============================================================

(defn compile-form
  "Compile a Clojure form to a Janet source string."
  [form]
  (let [ast (analyze-form form @{})
        buf @""]
    (emit-ast ast buf)
    (string buf)))

(defn eval-janet-source
  "Parse and evaluate a Janet source string.
  Uses the proper parser→produce→eval pipeline so special forms work."
  [source]
  (def p (parser/new))
  (parser/consume p source)
  (parser/eof p)
  (def form (parser/produce p))
  (eval form))

(defn compile-and-eval
  "Compile a Clojure form to Janet source and evaluate it.
  Returns the result value."
  [form]
  (eval-janet-source (compile-form form)))
