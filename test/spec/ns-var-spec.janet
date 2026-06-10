# Specification: *ns* — the current-namespace dynamic var (stage 3).
# *ns* holds the current NAMESPACE OBJECT; (str *ns*) is its name; it tracks
# in-ns at the top level and works with the ns-introspection fns.
(use ../support/harness)

(defspec "*ns* / identity & printing"
  ["str of *ns*"        "\"user\""  "(str *ns*)"]
  ["ns-name of *ns*"    "(quote user)" "(ns-name *ns*)"]
  ["*ns* is find-ns"    "true"   "(= (ns-name *ns*) (ns-name (find-ns (quote user))))"]
  ["*ns* not a map"     "false"  "(map? *ns*)"]
  ["tracks in-ns"       "\"jolt.test-ns-a\"" "(do (in-ns (quote jolt.test-ns-a)) (str *ns*))"]
  ["in-ns returns ns"   "\"jolt.test-ns-b\"" "(str (in-ns (quote jolt.test-ns-b)))"]
  ["usable with ns fns" "true"
   "(do (require (quote clojure.string)) (alias (quote nsv) (quote clojure.string)) (some? (get (ns-aliases *ns*) (quote nsv))))"]
  ["ns-unalias via *ns*" "true"
   "(do (require (quote clojure.string)) (alias (quote nsw) (quote clojure.string)) (ns-unalias *ns* (quote nsw)) (nil? (get (ns-aliases *ns*) (quote nsw))))"])
