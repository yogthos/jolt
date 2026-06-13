# Success-type checking (RFC 0006, jolt-y3b). The structural inference of
# RFC 0005, reused as a loose checker: flag a core-fn call ONLY when an argument
# is PROVABLY the wrong type (concrete and in the op's throwing error domain).
# Ambiguous cases (:any, unions, :truthy) are accepted — no false positives.
(import ../../src/jolt/api :as api)
(import ../../src/jolt/backend :as backend)
(import ../../src/jolt/types :as types)
(import ../../src/jolt/reader :as reader)

(print "Success-type checking (jolt-y3b)...")

(os/setenv "JOLT_DIRECT_LINK" "1")
(def ctx (api/init {:compile? true}))
(def pns (types/ctx-find-ns ctx "jolt.passes"))
(def check (types/var-get (types/ns-find pns "check-form")))

# diagnostics (a Janet tuple of diag structs) for a source form
(defn diags [src]
  (api/normalize-pvecs (check (backend/analyze-form ctx (reader/parse-string src)))))
(defn nd [src] (length (diags src)))

# --- provably wrong: REPORTED ------------------------------------------------
(assert (= 1 (nd "(inc \"x\")")) "inc on a string")
(assert (= 1 (nd "(+ 1 \"x\")")) "+ with a string arg")
(assert (= 1 (nd "(count :foo)")) "count of a keyword")
(assert (= 1 (nd "(count 5)")) "count of a number")
(assert (= 1 (nd "(first 42)")) "first of a number")
(assert (= 1 (nd "(nth :k 0)")) "nth of a keyword")
(assert (= 1 (nd "(let [n \"x\"] (inc n))")) "inc on a let-bound string")
(assert (= 1 (nd "(inc (count :k))")) "inner count of keyword reported (inc of :num is fine)")

# --- ambiguous / lenient: ACCEPTED (no false positive) -----------------------
(assert (= 0 (nd "(:k 5)")) "keyword lookup on a number returns nil, not an error")
(assert (= 0 (nd "(get 5 :k)")) "get on a number returns nil, not an error")
(assert (= 0 (nd "(fn [x] (inc x))")) "inc on an unknown (:any) param accepted")
(assert (= 0 (nd "(fn [c] (inc (if c 1 \"x\")))")) "inc on a {:num | :str} branch -> :any, accepted")
(assert (= 0 (nd "(count \"ab\")")) "count of a string is fine")
(assert (= 0 (nd "(count [1 2 3])")) "count of a vector is fine")
(assert (= 0 (nd "(first [1 2 3])")) "first of a vector is fine")
(assert (= 0 (nd "(inc (count [1 2 3]))")) "count of vector + inc of :num both fine")
(assert (= 0 (nd "(inc (first [1 2 3]))")) "first of vector -> :num, inc fine")

# --- bounded unions (jolt-pz5): report only when EVERY member is in the error
# domain; accept when any member is valid. Differing branches used to collapse
# to :any (accepted); now they form {:union #{...}} and are checked per-member.
(assert (= 1 (nd "(fn [c] (inc (if c \"a\" :k)))"))
        "inc of {:str | :kw} — every member non-number — reported")
(assert (= 0 (nd "(fn [c] (inc (if c 1 \"x\")))"))
        "inc of {:num | :str} — :num is fine — still accepted")
(assert (= 1 (nd "(fn [c] (count (if c :k 5)))"))
        "count of {:kw | :num} — both non-seqable — reported")
(assert (= 0 (nd "(fn [c] (count (if c :k \"ab\")))"))
        "count of {:kw | :str} — :str is seqable — accepted")
(assert (= 1 (nd "(fn [c] (inc (if c \"a\" (if c :k :j))))"))
        "inc of nested all-non-number union reported")
(assert (= 0 (nd "(fn [c] (inc (if c \"a\" (if c :k 1))))"))
        "inc of union with a buried :num member accepted")
# a union is opaque to structural specialization — it keeps the dynamic guard,
# exactly like :any, so a keyword lookup over it is never mis-specialized.
(assert (= 0 (nd "(fn [c] (:r (if c {:r 1} {:g 2})))"))
        "keyword lookup over a struct union is accepted (no false positive)")

# --- the diagnostic carries op + type + a message ----------------------------
(def one (in (diags "(inc \"x\")") 0))
(assert (= "inc" (get one :op)) "diagnostic names the op")
(assert (string/find "number" (get one :msg)) "message says a number is required")

# --- end-to-end: strictness drives compilation (decoupled from :inline?) -----
# error mode aborts a provably-wrong form's compilation; a correct form compiles.
(os/setenv "JOLT_TYPE_CHECK" "error")
(assert (not (first (protect (api/eval-string ctx "(count :nope)"))))
        "error mode aborts a provably-wrong form")
(assert (first (protect (api/eval-string ctx "(count [1 2 3])")))
        "error mode accepts a correct form")
(os/setenv "JOLT_TYPE_CHECK" "off")

(print "Success-type checking passed!")
