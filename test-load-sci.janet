(use ./src/jolt/evaluator)
(use ./src/jolt/types)
(use ./src/jolt/reader)
(use ./src/jolt/api)

(def ctx (init))

(defn load-file-quiet [ctx fp stop-at]
  (def src (slurp fp))
  (var s src)
  (var c 0)
  (var good 0)
  (var bad 0)
  (while (and (> (length (string/trim s)) 0) (or (not stop-at) (< c stop-at)))
    (def pr (protect (parse-next s)))
    (if (not (pr 0)) (do (printf "%s PARSE CRASH: %q\n" fp (pr 1)) (break)))
    (let [[f r] (pr 1)]
      (set s r)
      (++ c)
      (if (not (nil? f))
        (let [pr2 (protect (eval-form ctx @{} f))]
          (if (pr2 0) (++ good) (++ bad))))))
  {:count c :good good :bad bad})

(each fp ["/Users/yogthos/src/sci/src/sci/impl/macros.cljc"
          "/Users/yogthos/src/sci/src/sci/impl/protocols.cljc"
          "/Users/yogthos/src/sci/src/sci/impl/utils.cljc"
          "/Users/yogthos/src/sci/src/sci/impl/types.cljc"
          "/Users/yogthos/src/sci/src/sci/impl/unrestrict.cljc"]
  (load-file-quiet ctx fp nil))

(load-file-quiet ctx "/Users/yogthos/src/sci/src/sci/impl/vars.cljc" 27)
(load-file-quiet ctx "/Users/yogthos/src/sci/src/sci/lang.cljc" nil)

# Summary
(printf "\nSummary:\n")
(printf "ns: %s\n" (ctx-current-ns ctx))

# Try loading sci.core
(print "\nLoading sci.core...")
(def r (load-file-quiet ctx "/Users/yogthos/src/sci/src/sci/core.cljc" nil))
(printf "sci.core: %d forms, %d ok, %d fail\n" (r :count) (r :good) (r :bad))

(printf "ns: %s\n" (ctx-current-ns ctx))
