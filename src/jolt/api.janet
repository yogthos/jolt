# Jolt Public API
# High-level interface for the Clojure-on-Janet interpreter.

(use ./types)
(use ./reader)
(use ./evaluator)
(use ./core)
(use ./compiler)
(use ./loader)

(defn- load-persistent-structures
  "Load immutable persistent data structures and swap clojure.core bindings."
  [ctx]
  (def source (slurp "src/jolt/clojure/lang/persistent_vector.clj"))
  (var cur source)
  (while (> (length (string/trim cur)) 0)
    (def [form rest] (parse-next cur))
    (set cur rest)
    (when (not (nil? form))
      (eval-form ctx @{} form)))
  (let [core-ns (ctx-find-ns ctx "clojure.core")
        pv-ns (ctx-find-ns ctx "jolt.lang.persistent-vector")]
    (ns-intern core-ns "vec" (var-get (ns-find pv-ns "vector")))
    (ns-intern core-ns "vector" (var-get (ns-find pv-ns "vector")))
    (ns-intern core-ns "vector?" (var-get (ns-find pv-ns "vector?")))))

(defn init
  "Create a new Jolt evaluation context.
  opts may contain:
    :namespaces — map of {ns-name → {sym → value, ...}, ...}
    :mutable?   — use Janet mutable data structures instead of persistent
    :compile?   — enable compilation of Clojure forms to Janet"
  [&opt opts]
  (default opts {})
  (let [ctx (make-ctx opts)
        mutable? (get opts :mutable?)]
    (init-core! ctx)
    (if mutable?
      nil
      (load-persistent-structures ctx))
    ctx))

(defn eval-string
  "Evaluate a Clojure source string in a Jolt context.
  When :compile? is enabled, compiles to Janet source and evaluates via Janet.
  Stateful forms (def, defmacro, ns, deftype) always use the interpreter."
  [ctx s]
  (let [compile? (get (ctx :env) :compile?)
        form (parse-string s)]
    (if (and compile? (array? form))
      # Check if this is a stateful form that needs the interpreter
      (let [first-form (first form)
            head-name (if (and (struct? first-form) (= :symbol (first-form :jolt/type)))
                       (first-form :name)
                       nil)]
        (if (or (= head-name "def") (= head-name "defmacro") (= head-name "ns")
                (= head-name "deftype") (= head-name "defmulti") (= head-name "defmethod")
                (= head-name "require") (= head-name "in-ns"))
          (eval-form ctx @{} form)
          (compile-and-eval form)))
      (eval-form ctx @{} form))))

(defn eval-string*
  "Evaluate a Clojure source string with explicit bindings."
  [ctx s bindings]
  (let [form (parse-string s)]
    (eval-form ctx bindings form)))

(defn compile-string
  "Compile a Clojure source string to Janet source.
  Returns the Janet source string."
  [s]
  (let [form (parse-string s)]
    (compile-form form)))

(defn compile-file
  "Compile a .clj file to Janet source and optionally eval it.
  When ctx has :compile? enabled, also evaluates the compiled forms.
  Returns the namespace name."
  [ctx filepath]
  (load-ns ctx filepath))
