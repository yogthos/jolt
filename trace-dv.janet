(use ./src/jolt/evaluator)
(use ./src/jolt/types)
(use ./src/jolt/reader)
(use ./src/jolt/api)

# Override resolve-sym with tracing
(def old-resolve-sym @{:private true})

# Monkey-patch eval-list to add tracing
(var orig-eval-list nil)
# Just add a direct trace in fn*

(def ctx (init))
(each fp ["/Users/yogthos/src/sci/src/sci/impl/macros.cljc"
          "/Users/yogthos/src/sci/src/sci/impl/protocols.cljc"
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

(def ls (slurp "/Users/yogthos/src/sci/src/sci/lang.cljc"))
(set s ls)
(while (> (length (string/trim s)) 0)
  (def [f r] (parse-next s)) (set s r)
  (if (not (nil? f)) (protect (eval-form ctx @{} f))))

# Load utils up to form 35
(def us (slurp "/Users/yogthos/src/sci/src/sci/impl/utils.cljc"))
(set s us) (set c 0)
(while (and (> (length (string/trim s)) 0) (< c 35))
  (def [f r] (parse-next s)) (set s r) (++ c)
  (if (not (nil? f))
    (let [pr (protect (eval-form ctx @{} f))]
      (if (not (pr 0))
        (printf "utils[%d]: %q\n" c (pr 1))))))

# Now inspect the dynamic-var fn in detail
(def ns (ctx-find-ns ctx "sci.impl.utils"))
(def dv (ns-find ns "dynamic-var"))
(def dv-fn (var-get dv))

# Evaluate (dynamic-var 'foo) manually
(def quoted-foo @[{:jolt/type :symbol :ns nil :name "quote"} {:jolt/type :symbol :ns nil :name "foo"}])
(def dv-call @[{:jolt/type :symbol :ns nil :name "dynamic-var"} quoted-foo])

(printf "Calling dynamic-var('foo):\n")
(def r1 (protect (eval-form ctx @{} dv-call)))
(printf "  result: %q\n" (if (r1 0) "OK" (r1 1)))
