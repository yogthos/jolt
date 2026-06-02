(use ../src/jolt/evaluator)
(use ../src/jolt/types)
(use ../src/jolt/reader)
(use ../src/jolt/api)

(def ctx (init))

(defn load-file [ctx path &opt quiet]
  (var s (slurp path))
  (var count 0)
  (var ok 0)
  (var fail 0)
  (var failures @[])
  (while (> (length (string/trim s)) 0)
    (def [form rest] (parse-next s))
    (set s rest)
    (++ count)
    (if (not (nil? form))
      (do
        (when (not quiet) (printf "eval form %d..." count) (flush))
        (if (try
               (do (eval-form ctx @{} form) true)
               ([err]
                 (when (not quiet) (printf " FAIL: %q\n" err))
                 (array/push failures {:form-number count :error (string err)})
                 false))
          (do (when (not quiet) (printf " OK\n")) (++ ok))
          (++ fail)))))
  {:ok ok :fail fail :total count :failures failures})

(def sci-base "vendor/sci/src/sci")

# ============================================================
# Phase 1: Core SCI files (known-good)
# ============================================================
(def core-order @[
  "impl/macros.cljc"
  "impl/protocols.cljc"
  "impl/types.cljc"
  "impl/unrestrict.cljc"
  "impl/vars.cljc"
  "lang.cljc"
  "impl/utils.cljc"
  "impl/namespaces.cljc"
  "core.cljc"
])

# ============================================================
# Phase 2: Internal namespaces — interop, parser, opts, analyzer, interpreter
# These need edamame stubs first
# ============================================================

# Create minimal edamame.core namespace for parser/interpreter
(def edn-ns (ctx-find-ns ctx "edamame.core"))
(defn edn-eof [] :edamame/eof)
(defn edn-reader [x] @{:s x :pos 0 :line 1 :col 1})
(defn edn-parse-string [s & opts] (parse-string s))

(def edn-parse-next (fn [& args]
  (def reader (args 0))
  (def s (reader :s))
  (def pos (reader :pos))
  (if (>= pos (length s)) (edn-eof)
    (let [[form new-pos] (read-form s pos)]
      (put reader :pos new-pos)
      (var lp pos)
      (while (< lp new-pos)
        (if (= (s lp) 10)
          (do (put reader :line (+ 1 (reader :line))) (put reader :col 1))
          (put reader :col (+ 1 (reader :col))))
        (++ lp))
      form))))

(ns-intern edn-ns "eof" edn-eof)
(ns-intern edn-ns "normalize-opts" (fn [opts] (if (= true opts) {:all true} (or opts {}))))
(ns-intern edn-ns "reader" edn-reader)
(ns-intern edn-ns "parse-string" edn-parse-string)
(ns-intern edn-ns "parse-string-all" (fn [s & opts] @[(edn-parse-string s)]))
(ns-intern edn-ns "parse-next" edn-parse-next)
(ns-intern edn-ns "continue" :edamame/continue)

# Create minimal tools.reader namespace
(def rt-ns (ctx-find-ns ctx "clojure.tools.reader.reader-types"))
(ns-intern rt-ns "indexing-push-back-reader" (fn [rdr] rdr))
(ns-intern rt-ns "string-push-back-reader" edn-reader)
(ns-intern rt-ns "source-logging-reader?" (fn [rdr] false))
(ns-intern rt-ns "get-line-number" (fn [rdr] (rdr :line)))
(ns-intern rt-ns "get-column-number" (fn [rdr] (rdr :col)))

# ============================================================
# Phase 3: Load internal SCI namespaces in dependency order
# ============================================================
(def internal-order @[
  # interop needs: types, utils, reflector(clj)
  "impl/interop.cljc"
  # opts needs: namespaces, types  
  "impl/opts.cljc"
  # parser needs: edamame, tools.reader, interop, types, utils
  "impl/parser.cljc"
])

(var total-ok 0)
(var total-fail 0)
(var all-failures @[])

# Phase 1: core
(each file core-order
  (def path (string sci-base "/" file))
  (printf "\n=== Loading %s ===\n" file)
  (def result (load-file ctx path))
  (printf "  Result: %d ok, %d fail, %d total\n" (result :ok) (result :fail) (result :total))
  (+= total-ok (result :ok))
  (+= total-fail (result :fail))
  (each f (result :failures)
    (array/push all-failures {:file file :form-number (f :form-number) :error (f :error)})))

# Phase 2: internal
(each file internal-order
  (def path (string sci-base "/" file))
  (printf "\n=== Loading %s (internal) ===\n" file)
  (def result (load-file ctx path))
  (printf "  Result: %d ok, %d fail, %d total\n" (result :ok) (result :fail) (result :total))
  (+= total-ok (result :ok))
  (+= total-fail (result :fail))
  (each f (result :failures)
    (array/push all-failures {:file file :form-number (f :form-number) :error (f :error)})))

(printf "\n==============================\n")
(printf "TOTAL: %d ok, %d fail, %d total\n" total-ok total-fail (+ total-ok total-fail))
(printf "==============================\n")

# Check namespace binding counts
(printf "\n--- Namespace bindings ---\n")
(each nsn ["sci.impl.interop" "sci.impl.opts" "sci.impl.parser" "sci.impl.analyzer" "sci.impl.interpreter"]
  (def ns (ctx-find-ns ctx nsn))
  (printf "%s: %d bindings\n" nsn (if ns (length (keys (ns-map ns))) 0)))

(when (> (length all-failures) 0)
  (printf "\n=== FAILURES ===\n")
  (each f all-failures
    (printf "[%s:%d] %s\n" (f :file) (f :form-number) (f :error))))
