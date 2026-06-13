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
(reader/track-positions! true)   # record form positions (jolt-fqy)
(def ctx (api/init {:compile? true}))
(def pns (types/ctx-find-ns ctx "jolt.passes"))
(def check (types/var-get (types/ns-find pns "check-form")))

# diagnostics (a Janet tuple of diag structs) for a source form
(defn diags [src]
  (api/normalize-pvecs (check (backend/analyze-form ctx (reader/parse-string src)))))
(defn nd [src] (length (diags src)))
# strict mode (jolt-zo1): also report provably-wrong calls to user fns
(defn nds [src]
  (length (api/normalize-pvecs
            (check (backend/analyze-form ctx (reader/parse-string src)) true))))

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

# --- calling a non-function (jolt-wwy): :num and :str are not callable --------
(assert (= 1 (nd "(5 1)")) "calling a number is reported")
(assert (= 1 (nd "(\"hi\" 0)")) "calling a string is reported")
(assert (= 1 (nd "((+ 1 2) :k)")) "calling an arithmetic result (a :num) is reported")
(assert (= 1 (nd "(let [n 5] (n 1))")) "calling a let-bound number is reported")
(assert (= 1 (nd "(let [s \"x\"] (s 0))")) "calling a let-bound string is reported")
# (a var holding a number, e.g. (def nn 5) (nn 1), is caught in direct-link
# mode via vtype-box; the standalone checker has no var value types)
# callable values: keyword/map/vector/set as IFn — NOT reported
(assert (= 0 (nd "(:k {:k 1})")) "keyword call is fine")
(assert (= 0 (nd "({:a 1} :a)")) "map call is fine")
(assert (= 0 (nd "([10 20] 1)")) "vector call is fine")
(assert (= 0 (nd "(#{1 2} 1)")) "set call is fine")
(assert (= 0 (nd "(fn [c] ((if c 1 :k) 0))")) "union {:num | :kw} callee accepted (:kw is callable)")
(assert (= 0 (nd "(fn [f] (f 1))")) "calling an unknown (:any) param accepted")
(assert (= 1 (nd "(fn [c] ((if c 1 \"x\") 0))")) "union {:num | :str} callee — both non-callable — reported")

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

# --- user-function error domains (jolt-zo1), opt-in strict mode --------------
# A call passing a provably-wrong type to a user fn whose body requires
# otherwise is reported ONLY in strict mode; the default level never fires on
# user fns (closed-world soundness boundary).
(assert (= 0 (nd  "(do (defn ufa [x] (+ x 1)) (ufa \"s\"))"))
        "user-fn wrong call NOT reported at the default level")
(assert (= 1 (nds "(do (defn ufa [x] (+ x 1)) (ufa \"s\"))"))
        "strict: arithmetic fn called with a string is reported")
(assert (= 0 (nds "(do (defn ufb [x] (+ x 1)) (ufb 5))"))
        "strict: same fn called with a number is accepted")
(assert (= 0 (nds "(do (defn ufc [x] (:k x)) (ufc \"s\"))"))
        "strict: a body that uses the param leniently is not reported")
# cross-form: a def registered by an earlier check is visible to a later call
(nds "(defn ufd [x] (count x))")
(assert (= 1 (nds "(ufd 42)"))
        "strict: cross-form call to a seq-only fn with a number is reported")
(assert (= 0 (nds "(do (defn ^:redef ufe [x] (+ x 1)) (ufe \"s\"))"))
        "strict: a ^:redef fn is not a stable requirement, not reported")
(assert (= 1 (nds "(do (defn ufrec [x] (ufrec (+ x 1))) (ufrec \"s\"))"))
        "strict: self-recursion terminates (cycle guard) and the (+ x 1) on a string is reported once")
# wrong arity to a user fn (jolt-wwy), strict mode: the registered fixed arity
# makes a mismatched call provably throw, regardless of argument types
(assert (= 1 (nds "(do (defn uar [x y] (+ x y)) (uar 1))"))
        "strict: 2-arg fn called with 1 arg is reported")
(assert (= 1 (nds "(do (defn uar2 [x] x) (uar2 1 2 3))"))
        "strict: 1-arg fn called with 3 args is reported")
(assert (= 0 (nds "(do (defn uar3 [x y] (+ x y)) (uar3 1 2))"))
        "strict: correct arity accepted")
(assert (= 0 (nd "(do (defn uar4 [x y] (+ x y)) (uar4 1))"))
        "default level does NOT report user-fn arity (closed-world, opt-in)")
(assert (= 0 (nds "(do (defn ^:redef uar5 [x y] (+ x y)) (uar5 1))"))
        "strict: ^:redef fn arity not checked (could be redefined)")

# --- the diagnostic carries op + type + a message ----------------------------
(def one (in (diags "(inc \"x\")") 0))
(assert (= "inc" (get one :op)) "diagnostic names the op")
(assert (string/find "number" (get one :msg)) "message says a number is required")
# --- the diagnostic carries the offending form's source offset (jolt-fqy) -----
(assert (= 0 (get one :pos)) "diagnostic carries :pos (offset 0 for a single form)")
(def nested (in (diags "(do 1 2 (inc :k))") 0))
(assert (= 8 (get nested :pos))
        "the inner (inc :k) form is positioned at its own offset, not the do's")

# --- end-to-end: strictness drives compilation (decoupled from :inline?) -----
# error mode aborts a provably-wrong form's compilation; a correct form compiles.
(os/setenv "JOLT_TYPE_CHECK" "error")
(assert (not (first (protect (api/eval-string ctx "(count :nope)"))))
        "error mode aborts a provably-wrong form")
(assert (first (protect (api/eval-string ctx "(count [1 2 3])")))
        "error mode accepts a correct form")
(os/setenv "JOLT_TYPE_CHECK" "off")

(print "Success-type checking passed!")
