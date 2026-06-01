# Jolt Evaluator
# Direct interpreter for Clojure forms on Janet.

(use ./types)

(defn- sym-name?
  [sym-s name-str]
  (and (struct? sym-s) (= :symbol (sym-s :jolt/type)) (= name-str (sym-s :name))))

(defn- special-symbol?
  [name]
  (or (= name "quote") (= name "syntax-quote") (= name "unquote")
      (= name "unquote-splicing") (= name "do") (= name "if")
      (= name "def") (= name "fn*") (= name "let*") (= name "loop*")
      (= name "recur")))

(var eval-form nil)

(defn- syntax-quote*
  [ctx bindings form]
  (cond
    (and (array? form) (> (length form) 0) (sym-name? (first form) "unquote"))
    (eval-form ctx bindings (in form 1))
    (and (array? form) (> (length form) 0) (sym-name? (first form) "unquote-splicing"))
    (error "~@ used outside of a list or vector in syntax-quote")
    (or (number? form) (string? form) (keyword? form) (nil? form) (= true form) (= false form))
    form
    (and (struct? form) (= :symbol (form :jolt/type)))
    (if (nil? (form :ns))
      (if (special-symbol? (form :name)) form
        {:jolt/type :symbol :ns (ctx-current-ns ctx) :name (form :name)})
      form)
    (tuple? form)
    (do (var result @[]) (var i 0) (while (< i (length form))
      (let [item (in form i)]
        (if (and (array? item) (> (length item) 0) (sym-name? (first item) "unquote-splicing"))
          (each v (eval-form ctx bindings (in item 1)) (array/push result v))
          (array/push result (syntax-quote* ctx bindings item))))
      (++ i)) (tuple ;result))
    (array? form)
    (do (var result @[]) (var i 0) (while (< i (length form))
      (let [item (in form i)]
        (if (and (array? item) (> (length item) 0) (sym-name? (first item) "unquote-splicing"))
          (each v (eval-form ctx bindings (in item 1)) (array/push result v))
          (array/push result (syntax-quote* ctx bindings item))))
      (++ i)) result)
    (and (struct? form) (get form :jolt/type)) form
    (struct? form)
    (do (var kvs @[]) (each k (keys form)
      (array/push kvs (syntax-quote* ctx bindings k))
      (array/push kvs (syntax-quote* ctx bindings (get form k)))) (struct ;kvs))
    form))

(defn- resolve-var
  [ctx bindings sym-s]
  (let [name (sym-s :name) ns (sym-s :ns)]
    (if (not (nil? ns))
      (let [target-ns (ctx-find-ns ctx ns)] (ns-find target-ns name))
      (if (get bindings name) nil
        (let [current-ns (ctx-current-ns ctx) ns (ctx-find-ns ctx current-ns)] (ns-find ns name))))))

(defn- sym-name-str
  [sym-s]
  (if (sym-s :ns) (string (sym-s :ns) "/" (sym-s :name)) (sym-s :name)))

(defn- eval-require
  [ctx spec]
  (let [ns-sym (in spec 0)
        ns-name (sym-name-str ns-sym)]
    (var alias nil)
    (var i 1)
    (let [slen (length spec)]
      (while (< i slen)
        (let [item (in spec i)]
          (if (or (= item :as) (and (struct? item) (= :symbol (item :jolt/type)) (= "as" (item :name))))
            (do
              (def alias-sym (in spec (+ i 1)))
              (set alias (alias-sym :name))
              (set i slen))
            (++ i)))))
    (ctx-find-ns ctx ns-name)
    (when alias
      (let [current-ns (ctx-find-ns ctx (ctx-current-ns ctx))]
        (ns-import current-ns alias ns-name)))
    nil))

(defn- resolve-sym
  [ctx bindings sym-s]
  (let [name (sym-s :name) ns (sym-s :ns)]
    (if (not (nil? ns))
      (let [current-ns (ctx-find-ns ctx (ctx-current-ns ctx)) aliased-ns (ns-import-lookup current-ns ns)]
        (if aliased-ns
          (let [target-ns (ctx-find-ns ctx aliased-ns) v (ns-find target-ns name)]
            (if v (var-get v) (error (string "Unable to resolve symbol: " ns "/" name))))
          (let [target-ns (ctx-find-ns ctx ns) v (ns-find target-ns name)]
            (if v (var-get v) (error (string "Unable to resolve symbol: " ns "/" name))))))
      (let [local (get bindings name)]
        (if (not (nil? local)) local
          (let [current-ns (ctx-current-ns ctx) ns (ctx-find-ns ctx current-ns) v (ns-find ns name)]
            (if v (var-get v)
              # Check clojure.core as auto-referred fallback
              (let [core-ns (ctx-find-ns ctx "clojure.core")
                    core-v (ns-find core-ns name)]
                (if core-v
                  (var-get core-v)
                  # Fall back to Janet's global environment
                  (let [root-env (fiber/getenv (fiber/current))
                        entry (in root-env (symbol name))]
                    (if (not (nil? entry))
                      (if (table? entry) (entry :value) entry)
                      (error (string "Unable to resolve symbol: " name)))))))))))))

# Dispatch a special form by its string name. Each branch is a standalone
# expression that returns the value directly — no cond, no nested if chains.
# We use a local function per form and call the matching one.
(defn- eval-list
  [ctx bindings form]
  (def first-form (first form))
  (def name (first-form :name))
  (match name
    "quote" (in form 1)
    "syntax-quote" (syntax-quote* ctx bindings (in form 1))
    "unquote" (error "Unquote not valid outside of syntax-quote")
    "unquote-splicing" (error "Unquote-splicing not valid outside of syntax-quote")
    "do" (do
           (var result nil)
           (var i 1)
           (let [len (length form)]
             (while (< i len)
               (set result (eval-form ctx bindings (in form i)))
               (++ i)))
           result)
    "if" (let [test-val (eval-form ctx bindings (in form 1))]
           (if (and (not (nil? test-val)) (not (= false test-val)))
             (eval-form ctx bindings (in form 2))
             (if (> (length form) 3) (eval-form ctx bindings (in form 3)) nil)))
    "def" (let [name-sym (in form 1)
                val (eval-form ctx bindings (in form 2))
                ns-name (ctx-current-ns ctx)
                ns (ctx-find-ns ctx ns-name)]
            (ns-intern ns (name-sym :name) val)
            (var-get (ns-intern ns (name-sym :name))))
    "ns" (let [ns-name (sym-name-str (in form 1))
               clauses (tuple/slice form 2)]
           (ctx-set-current-ns ctx ns-name)
           (ctx-find-ns ctx ns-name)
           (var result nil)
           (var i 0)
           (let [clen (length clauses)]
             (while (< i clen)
               (let [clause (in clauses i)]
                 (if (and (array? clause) (> (length clause) 0) (= :require (first clause)))
                   (let [specs (tuple/slice clause 1)
                         slen (length specs)]
                     (var j 0)
                     (while (< j slen)
                       (let [s (in specs j)]
                         (eval-require ctx s))
                       (++ j))
                     (set i (+ i 1)))
                   (do (set result clause) (++ i))))))
           result)
    "require" (let [spec (eval-form ctx bindings (in form 1))]
                 (if (and (tuple? spec) (> (length spec) 0))
                   (eval-require ctx spec)
                   (error "require expects a vector spec")))
    "in-ns" (let [ns-name (sym-name-str (in form 1))]
              (ctx-set-current-ns ctx ns-name)
              (ctx-find-ns ctx ns-name)
              nil)
    "fn*" (let [args-form (in form 1)
                body (tuple/slice form 2)
                arg-names (map |($ :name) args-form)]
            (var self nil)
            (set self (fn [& fn-args]
              (var fn-bindings @{})
              (table/setproto fn-bindings bindings)
              (var i 0)
              (each arg-name arg-names
                (put fn-bindings arg-name (fn-args i))
                (++ i))
              (put fn-bindings :jolt/loop-fn self)
              (var result nil)
              (each body-form body
                (set result (eval-form ctx fn-bindings body-form)))
              result))
            self)
    "let*" (let [bind-vec (in form 1)
                 body (tuple/slice form 2)]
             (var new-bindings @{})
             (table/setproto new-bindings bindings)
             (var i 0)
             (let [len (length bind-vec)]
               (while (< i len)
                 (let [sym (bind-vec i)
                       val (eval-form ctx new-bindings (bind-vec (+ i 1)))]
                   (put new-bindings (sym :name) val)
                   (+= i 2))))
             (var result nil)
             (each body-form body
               (set result (eval-form ctx new-bindings body-form)))
             result)
    "loop*" (let [bind-vec (in form 1)
                  body (tuple/slice form 2)
                  init-vals @[]
                  sym-names @[]]
              (var i 0)
              (while (< i (length bind-vec))
                (array/push init-vals (eval-form ctx bindings (bind-vec (+ i 1))))
                (array/push sym-names ((bind-vec i) :name))
                (+= i 2))
              (var loop-fn nil)
              (set loop-fn (fn [& args]
                (var loop-bindings @{})
                (table/setproto loop-bindings bindings)
                (var j 0)
                (each sn sym-names
                  (put loop-bindings sn (args j))
                  (++ j))
                (put loop-bindings :jolt/loop-fn loop-fn)
                (var result nil)
                (each body-form body
                  (set result (eval-form ctx loop-bindings body-form)))
                result))
              (apply loop-fn init-vals))
    "recur" (let [loop-fn (get bindings :jolt/loop-fn)]
              (if (nil? loop-fn)
                (error "recur used outside of loop* or fn*")
                (let [args (map |(eval-form ctx bindings $) (tuple/slice form 1))]
                  (apply loop-fn args))))
    # default: function application — check for macros
    (if (and (struct? first-form) (= :symbol (first-form :jolt/type)))
      (let [v (resolve-var ctx bindings first-form)]
        (if (and v (var-macro? v))
          (let [macro-fn (var-get v)
                args (tuple/slice form 1)]
            (eval-form ctx bindings (apply macro-fn args)))
          (let [f (eval-form ctx bindings first-form)
                args (map |(eval-form ctx bindings $) (tuple/slice form 1))]
            (apply f args))))
      (let [f (eval-form ctx bindings first-form)
            args (map |(eval-form ctx bindings $) (tuple/slice form 1))]
        (apply f args)))))

(set eval-form (fn [ctx bindings form]
  (cond
    (nil? form) nil
    (number? form) form
    (string? form) form
    (keyword? form) form
    (bytes? form) form
    (buffer? form) form
    (tuple? form) (tuple/slice (map |(eval-form ctx bindings $) form))
    (struct? form)
    (if (= :symbol (form :jolt/type))
      (resolve-sym ctx bindings form)
      (if (get form :jolt/type)
        (error (string "Unexpected tagged form: " (form :jolt/type)))
        form))
    (array? form)
    (if (= 0 (length form))
      @[]
      (eval-list ctx bindings form))
    form)))
