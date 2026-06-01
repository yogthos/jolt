# Jolt Public API
# High-level interface for the Clojure-on-Janet interpreter.

(use ./types)
(use ./reader)
(use ./evaluator)
(use ./core)

(defn init
  "Create a new Jolt evaluation context, optionally with opts.
  (init)          — empty context with clojure.core loaded
  (init opts)     — context with opts and clojure.core loaded
  
  opts may contain:
    :namespaces — map of {ns-name → {sym → value, ...}, ...}"
  [&opt opts]
  (default opts nil)
  (let [ctx (make-ctx opts)]
    (init-core! ctx)
    ctx))

(defn eval-string
  "Evaluate a Clojure source string in a Jolt context.
  (eval-string ctx s) → value
  
  Returns the result of evaluating the first form in s."
  [ctx s]
  (let [form (parse-string s)]
    (eval-form ctx @{} form)))

(defn eval-string*
  "Evaluate a Clojure source string in a Jolt context.
  Like eval-string but with explicit bindings.
  (eval-string* ctx s bindings) → value"
  [ctx s bindings]
  (let [form (parse-string s)]
    (eval-form ctx bindings form)))
