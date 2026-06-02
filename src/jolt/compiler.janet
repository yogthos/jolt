# Jolt Compiler
# Source-to-source: Clojure forms → Janet source
# Two-phase: analyze-form (classify) → emit-ast (generate)

# Mapping from Clojure core names to Janet function names.
# Populated at init time from the core-bindings map.
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
  "Check if a form is a self-evaluating literal (not a symbol)."
  [form]
  (or (nil? form) (= true form) (= false form)
      (number? form) (string? form) (keyword? form) (bytes? form) (buffer? form)))

(defn- sym-name-str
  [sym-s]
  (if (sym-s :ns) (string (sym-s :ns) "/" (sym-s :name)) (sym-s :name)))

(defn- special-form?
  [name]
  (or (= name "quote") (= name "syntax-quote") (= name "do")
      (= name "if") (= name "def") (= name "defmacro") (= name "fn*")
      (= name "let*") (= name "loop*") (= name "recur") (= name "throw")
      (= name "try") (= name "set!") (= name "var") (= name ".")
      (= name "new") (= name "deftype") (= name "instance?")
      (= name "defmulti") (= name "defmethod") (= name "locking")))

# ============================================================
# Analyzer — Clojure form → annotated AST node {:op ...}
# ============================================================

(defn analyze-form
  "Analyze a Clojure form and return an AST node with :op key.
  Takes bindings (table) for local symbol classification.
  Recursively analyzes sub-expressions."
  [form bindings]
  (cond
    # Literals
    (literal? form)
    {:op :const :val form}

    # Symbols
    (and (struct? form) (= :symbol (form :jolt/type)))
    (let [name (form :name)
          ns (form :ns)]
      (if ns
        {:op :qualified-symbol :ns ns :name name}
        # Check local bindings first (let vars, fn params)
        (if (get bindings name)
          {:op :local :name name}
          (if (and (not (special-form? name)) (get core-renames name))
            {:op :core-symbol :name name :janet-name (get core-renames name)}
            {:op :symbol :name name}))))

    # Lists/arrays
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
                      # Augment bindings with param names so body refs are :local
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
                       # Analyze binding init values with outer bindings
                       n-binding-slots (length bind-vec)
                       binding-pairs (do
                                       (var pairs @[])
                                       (var i 0)
                                       (while (< i n-binding-slots)
                                         (let [sym-s (in bind-vec i)
                                               name (if (struct? sym-s) (sym-s :name) sym-s)
                                               val-form (if (< (+ i 1) n-binding-slots) (in bind-vec (+ i 1)) nil)
                                               val-ast (if val-form (analyze-form val-form bindings) {:op :const :val nil})]
                                           (array/push pairs {:name name :init val-ast})
                                           (+= i 2)))
                                       pairs)
                       # Augment bindings with let-bound names for body analysis
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
          # Default: function invocation
          (let [f-ast (analyze-form first-form bindings)
                args (map |(analyze-form $ bindings) (tuple/slice form 1))]
            {:op :invoke :fn f-ast :args args}))
        # Non-symbol head: function invocation
        (let [f-ast (analyze-form first-form bindings)
              args (map |(analyze-form $ bindings) (tuple/slice form 1))]
          {:op :invoke :fn f-ast :args args})))

    # Tuples (vectors)
    (tuple? form)
    (let [items (map |(analyze-form $ bindings) form)]
      {:op :vector :items items})

    # Structs (maps)
    (struct? form)
    {:op :map :form form}

    # Fallback
    {:op :const :val form}))

# ============================================================
# Emitter — AST node → Janet source string
# ============================================================

(defn- emit-const
  "Emit a literal constant value."
  [val buf]
  (cond
    (nil? val) (buffer/push buf "nil")
    (= true val) (buffer/push buf "true")
    (= false val) (buffer/push buf "false")
    (string? val) (do (buffer/push buf "\"") (buffer/push buf val) (buffer/push buf "\""))
    (keyword? val) (do (buffer/push buf ":") (buffer/push buf (string val)))
    (buffer/push buf (string val))))

# Forward declaration for mutual recursion
(var emit-ast nil)

(defn- emit-do
  [statements ret buf]
  (buffer/push buf "(do ")
  (var i 0)
  (let [n (length statements)]
    (while (< i n)
      (emit-ast (in statements i) buf)
      (buffer/push buf " ")
      (++ i)))
  (when ret
    (emit-ast ret buf))
  (buffer/push buf ")"))

(defn- emit-if
  [test then else buf]
  (buffer/push buf "(if ")
  (emit-ast test buf)
  (buffer/push buf " ")
  (emit-ast then buf)
  (when else
    (buffer/push buf " ")
    (emit-ast else buf))
  (buffer/push buf ")"))

(defn- emit-def
  [name-sym init buf]
  (buffer/push buf "(def ")
  (buffer/push buf (name-sym :name))
  (buffer/push buf " ")
  (emit-ast init buf)
  (buffer/push buf ")"))

(defn- emit-fn
  [params body buf]
  (buffer/push buf "(fn [")
  (var i 0)
  (let [n (length params)]
    (while (< i n)
      (let [p (in params i)]
        (buffer/push buf (if (struct? p) (p :name) (string p))))
      (when (< (+ i 1) n)
        (buffer/push buf " "))
      (++ i)))
  (buffer/push buf "] ")
  (emit-ast body buf)
  (buffer/push buf ")"))

(defn- emit-let
  [binding-pairs body buf]
  (buffer/push buf "(let [")
  (var i 0)
  (let [n (length binding-pairs)]
    (while (< i n)
      (let [bp (in binding-pairs i)]
        (buffer/push buf (bp :name))
        (buffer/push buf " ")
        (emit-ast (bp :init) buf)
        (when (< (+ i 1) n) (buffer/push buf " ")))
      (++ i)))
  (buffer/push buf "] ")
  (emit-ast body buf)
  (buffer/push buf ")"))

(defn- emit-invoke
  [f-ast args buf]
  (buffer/push buf "(")
  (emit-ast f-ast buf)
  (each arg args
    (buffer/push buf " ")
    (emit-ast arg buf))
  (buffer/push buf ")"))

(defn- emit-symbol
  [name buf]
  (buffer/push buf name))

(defn- emit-local
  [name buf]
  (buffer/push buf name))

(defn- emit-core-symbol
  [janet-name buf]
  (buffer/push buf janet-name))

(defn- emit-qualified-symbol
  [ns name buf]
  (buffer/push buf "(ns-get \"")
  (buffer/push buf ns)
  (buffer/push buf "\" \"")
  (buffer/push buf name)
  (buffer/push buf "\")"))

(defn- emit-vector
  [items buf]
  (buffer/push buf "[")
  (var i 0)
  (let [n (length items)]
    (while (< i n)
      (emit-ast (in items i) buf)
      (when (< (+ i 1) n) (buffer/push buf " "))
      (++ i)))
  (buffer/push buf "]"))

(defn- emit-map
  [form buf]
  (buffer/push buf (string form)))

(defn- emit-quote
  [expr buf]
  (buffer/push buf "'")
  (emit-ast (analyze-form expr @{}) buf))

(set emit-ast
  (fn [ast buf]
    (match (ast :op)
      :const (emit-const (ast :val) buf)
      :symbol (emit-symbol (ast :name) buf)
      :local (emit-local (ast :name) buf)
      :core-symbol (emit-core-symbol (ast :janet-name) buf)
      :qualified-symbol (emit-qualified-symbol (ast :ns) (ast :name) buf)
      :do (emit-do (ast :statements) (ast :ret) buf)
      :if (emit-if (ast :test) (ast :then) (ast :else) buf)
      :def (emit-def (ast :name) (ast :init) buf)
      :fn (emit-fn (ast :params) (ast :body) buf)
      :let (emit-let (ast :binding-pairs) (ast :body) buf)
      :invoke (emit-invoke (ast :fn) (ast :args) buf)
      :vector (emit-vector (ast :items) buf)
      :map (emit-map (ast :form) buf)
      :quote (emit-quote (ast :expr) buf)
      # Fallback for unknown ops
      (buffer/push buf (string "/* unhandled op: " (ast :op) " */")))))

(defn compile-form
  "Compile a Clojure form to a Janet source string."
  [form]
  (let [ast (analyze-form form @{})
        buf @""]
    (emit-ast ast buf)
    (string buf)))
