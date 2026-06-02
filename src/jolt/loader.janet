# Jolt Loader
# Namespace loading with optional compilation.
# Supports in-memory bytecode caching when :compile? is enabled.

(use ./reader)
(use ./compiler)
(use ./evaluator)

(defn load-ns
  "Load a Clojure namespace from a .clj file.
  When ctx has :compile? enabled, forms are compiled to Janet source,
  evaluated via Janet's evaluator, and cached.
  
  (load-ns ctx filepath) → namespace symbol string"
  [ctx filepath]
  (let [env (ctx :env)
        compile? (get env :compile?)
        cache (get env :compiled-cache)]
    
    (def source (slurp filepath))
    (var ns-name nil)
    (var remaining source)
    (var forms @[])
    
    # Parse all forms
    (while (> (length (string/trim remaining)) 0)
      (def [form rest] (parse-next remaining))
      (set remaining rest)
      (when (not (nil? form))
        (array/push forms form)
        # Extract ns name from the first ns form
        (when (and (nil? ns-name)
                   (array? form)
                   (> (length form) 0)
                   (and (struct? (first form))
                        (= :symbol ((first form) :jolt/type))
                        (= "ns" ((first form) :name))))
          (let [name-form (in form 1)]
            (set ns-name (if (struct? name-form) (name-form :name) (string name-form)))))))
    
    (when (nil? ns-name)
      (error (string "No ns form found in " filepath)))
    
    (if compile?
      (do
        # Compile each form and eval as Janet
        (var cached (get cache ns-name))
        (when (nil? cached)
          (set cached @[])
          (put cache ns-name cached))
        
        (each form forms
          (let [janet-src (compile-form form)]
            (array/push cached janet-src)
            (eval-janet-source janet-src)))
        ns-name)
      # Interpreter path
      (do
        (each form forms
          (eval-form ctx @{} form))
        ns-name))))

(defn compiled?
  "Check if a namespace has been compiled and cached."
  [ctx ns-name]
  (let [cache (get (ctx :env) :compiled-cache)]
    (not (nil? (get cache ns-name)))))

(defn get-compiled-forms
  "Get the compiled Janet source forms for a namespace."
  [ctx ns-name]
  (get (ctx :env) :compiled-cache ns-name))

(defn clear-compiled-cache
  "Clear the compiled form cache for a namespace or all namespaces."
  [ctx &opt ns-name]
  (let [cache (get (ctx :env) :compiled-cache)]
    (if ns-name
      (put cache ns-name nil)
      (loop [[k] :pairs cache] (put cache k nil)))))
