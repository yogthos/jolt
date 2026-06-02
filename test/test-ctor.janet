(use ../src/jolt/types)
(use ../src/jolt/api)
(use ../src/jolt/reader)
(use ../src/jolt/evaluator)

(def ctx (init))
(def sci-base "vendor/sci/src/sci")

(defn load [ctx path]
  (var s (slurp path))
  (while (> (length (string/trim s)) 0)
    (def [form rest] (parse-next s))
    (set s rest)
    (when (not (nil? form))
      (try (eval-form ctx @{} form) ([err] nil))))))

(each f ["impl/macros.cljc" "impl/protocols.cljc" "impl/types.cljc" "impl/unrestrict.cljc" "impl/vars.cljc" "lang.cljc" "impl/utils.cljc" "impl/namespaces.cljc"]
  (load ctx (string sci-base "/" f)))

# Check if utils/new-var exists
(def utils-ns (ctx-find-ns ctx "sci.impl.utils"))
(def new-var-v (if utils-ns (ns-find utils-ns "new-var") nil))
(printf "sci.impl.utils/new-var: %q\n" new-var-v)

# Check parser ns aliases
(def parser-ns (ctx-find-ns ctx "sci.impl.parser"))
(if parser-ns
  (do
    (printf "parser aliases: %q\n" (parser-ns :aliases))
    (printf "parser imports: %q\n" (parser-ns :imports))))

# Try resolving utils/new-var through alias
(printf "\nResolve utils/new-var: %q\n"
  (try (eval-string ctx "utils/new-var") ([err] (string "ERR: " err))))
