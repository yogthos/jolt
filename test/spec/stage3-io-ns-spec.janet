# Specification: Stage 3 turn 2b — host-classified IO fns, ns introspection,
# the thread-binding family, and load-string/eval as values. These were
# previously either missing or silently leaked from Janet's root environment.
(use ../support/harness)

(defspec "io / slurp, spit, printf, flush (host-classified)"
  ["slurp returns string" "true" "(string? (slurp \"project.janet\"))"]
  ["slurp content"       "true"  "(do (require (quote [clojure.string :as s])) (s/includes? (slurp \"project.janet\") \"jolt\"))"]
  ["spit + slurp round"  "\"hello\"" "(do (spit \"/tmp/jolt-spit-test.txt\" \"hello\") (slurp \"/tmp/jolt-spit-test.txt\"))"]
  ["spit append"         "\"ab\"" "(do (spit \"/tmp/jolt-spit-test.txt\" \"a\") (spit \"/tmp/jolt-spit-test.txt\" \"b\" :append true) (slurp \"/tmp/jolt-spit-test.txt\"))"]
  ["printf formats"      "\"x=1 y=a\"" "(with-out-str (printf \"x=%d y=%s\" 1 \"a\"))"]
  ["printf no newline"   "false" "(do (require (quote [clojure.string :as s])) (s/includes? (with-out-str (printf \"%d\" 1)) \"\\n\"))"]
  ["flush returns nil"   "nil"   "(flush)"]
  ["file-seq finds files" "true" "(do (require (quote [clojure.string :as s])) (boolean (some (fn [p] (s/ends-with? p \"project.janet\")) (file-seq \".\"))))"])

(defspec "ns / ns-map, ns-unmap, ns-refers"
  ["ns-map has var"      "true"  "(do (def nmv 1) (some? (get (ns-map (quote user)) (quote nmv))))"]
  ["ns-unmap removes"    "nil"   "(do (def nuv 1) (ns-unmap (quote user) (quote nuv)) (resolve (quote nuv)))"]
  ["ns-refers sees refer" "true" "(do (require (quote clojure.string)) (refer (quote clojure.string)) (some? (get (ns-refers (quote user)) (quote join))))"])

(defspec "vars / thread-binding family"
  ["bound? on def"       "true"  "(do (def bvv 1) (bound? (var bvv)))"]
  ["with-bindings* binds" "5"
   "(do (def ^:dynamic dynv 1) (with-bindings* (array-map (var dynv) 5) (fn [] dynv)))"]
  ["with-bindings* restores" "1"
   "(do (def ^:dynamic dynw 1) (with-bindings* (array-map (var dynw) 5) (fn [] nil)) dynw)"]
  ["with-bindings macro" "7"
   "(do (def ^:dynamic dynx 1) (with-bindings (array-map (var dynx) 7) dynx))"]
  ["thread-bound? inside" "[true false]"
   "(do (def ^:dynamic dyny 1) [(with-bindings* (array-map (var dyny) 2) (fn [] (thread-bound? (var dyny)))) (thread-bound? (var dyny))])"]
  ["bound-fn* conveys"   "9"
   "(do (def ^:dynamic dynz 1) (def f (with-bindings* (array-map (var dynz) 9) (fn [] (bound-fn* (fn [] dynz))))) (f))"]
  ["get-thread-bindings" "3"
   "(do (def ^:dynamic dyng 1) (with-bindings* (array-map (var dyng) 3) (fn [] (get (get-thread-bindings) (var dyng)))))"])

(defspec "eval & load-string as values"
  ["load-string evals all" "3"  "(load-string \"(def lsv 1) (+ lsv 2)\")"]
  ["eval as value"       "[2 3]" "(mapv eval [(quote (+ 1 1)) (quote (+ 1 2))])"]
  ["eval special still works" "3" "(eval (quote (+ 1 2)))"])

# clojure.edn is complete (jolt-b7y / jolt-0mb): sets, #uuid/#inst, :eof,
# and the :readers / :default opts (tag normalized from the reader's :#name
# keyword to the symbol Clojure keys :readers with).
(defspec "clojure.edn / opts"
  ["set literal"     "#{1 2}" "(do (require (quote [clojure.edn :as e0])) (e0/read-string \"#{1 2}\"))"]
  ["uuid tag"        "true"   "(do (require (quote [clojure.edn :as e0])) (uuid? (e0/read-string \"#uuid \\\"550e8400-e29b-41d4-a716-446655440000\\\"\")))"]
  ["inst tag"        "true"   "(do (require (quote [clojure.edn :as e0])) (inst? (e0/read-string \"#inst \\\"2020-01-01T00:00:00Z\\\"\")))"]
  [":eof on empty"   ":end"   "(do (require (quote [clojure.edn :as e0])) (e0/read-string {:eof :end} \"\"))"]
  [":readers custom tag" "[:custom 5]" "(do (require (quote [clojure.edn :as e0])) (e0/read-string {:readers {(quote custom) (fn [v] [:custom v])}} \"#custom 5\"))"]
  [":readers nested" "[6 8]"  "(do (require (quote [clojure.edn :as e0])) (e0/read-string {:readers {(quote w) (fn [v] (* 2 v))}} \"[#w 3 #w 4]\"))"]
  [":default fn"     "[:dflt 7]" "(do (require (quote [clojure.edn :as e0])) (e0/read-string {:default (fn [t v] [:dflt v])} \"#unknown 7\"))"]
  ["unknown tag throws" :throws "(do (require (quote [clojure.edn :as e0])) (e0/read-string \"#nope 1\"))"])
