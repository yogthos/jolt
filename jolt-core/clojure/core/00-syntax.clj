;; clojure.core — syntax tier. The control macros the compiler and every later
;; tier depend on (when/cond/and/or/...), expressed as defmacro. Loaded FIRST
;; (before 00-kernel), interpreted, so the macros exist before any code that uses
;; them is compiled — including the kernel tier, the self-hosted analyzer, and the
;; seq/coll tiers.
;;
;; CONSTRAINT: a macro here may use ONLY special forms (if/do/let*/fn*/not) and
;; core-renames SEED primitives (first/next/rest/nth/count/empty?/...). It must
;; NOT use kernel-tier fns (second/peek/subvec/...) or anything defined later —
;; those don't exist yet when this tier loads.

(defmacro when [test & body]
  `(if ~test (do ~@body)))

(defmacro when-not [test & body]
  `(if (not ~test) (do ~@body)))

(defmacro and [& exprs]
  (if (empty? exprs)
    true
    (if (empty? (rest exprs))
      (first exprs)
      `(let* [and# ~(first exprs)] (if and# (and ~@(rest exprs)) and#)))))

(defmacro or [& exprs]
  (if (empty? exprs)
    nil
    (if (empty? (rest exprs))
      (first exprs)
      `(let* [or# ~(first exprs)] (if or# or# (or ~@(rest exprs)))))))

;; :else (any truthy value) is just a test, so no special case — (if :else e ...)
;; takes e.
(defmacro cond [& clauses]
  (if (empty? clauses)
    nil
    `(if ~(first clauses) ~(nth clauses 1) (cond ~@(drop 2 clauses)))))

;; Threading: a list form threads x in as the first (->) or last (->>) arg; a bare
;; symbol becomes (form x). Recursive; the expand-once cache makes that free.
(defmacro -> [x & forms]
  (if (empty? forms)
    x
    (let [form (first forms)
          threaded (if (seq? form)
                     `(~(first form) ~x ~@(rest form))
                     `(~form ~x))]
      `(-> ~threaded ~@(rest forms)))))

(defmacro ->> [x & forms]
  (if (empty? forms)
    x
    (let [form (first forms)
          threaded (if (seq? form)
                     `(~(first form) ~@(rest form) ~x)
                     `(~form ~x))]
      `(->> ~threaded ~@(rest forms)))))

;; Forward declaration is a no-op on Jolt — the compiler resolves forward refs via
;; pending cells (matching the prior Janet macro).
(defmacro declare [& syms] `(do))

;; A fresh jolt symbol inside a macro body (a bare (gensym) returns a Janet symbol
;; the destructurer rejects). This defn compiles fine: by the time a tier triggers
;; the analyzer build the kernel is in place (the build is gated until then).
(defn- fresh-sym [] (symbol (str (gensym))))

;; cond->: thread expr through each (test form) pair, only when the test is truthy.
;; Linear nested let*, a distinct fresh symbol per step.
(defmacro cond-> [expr & clauses]
  (let [step (fn step [prev cls]
               (if (empty? cls)
                 prev
                 (let [t (first cls)
                       f (nth cls 1)
                       gn (fresh-sym)
                       call (if (seq? f) `(~(first f) ~prev ~@(rest f)) `(~f ~prev))]
                   `(let* [~gn (if ~t ~call ~prev)] ~(step gn (drop 2 cls))))))
        g0 (fresh-sym)]
    `(let* [~g0 ~expr] ~(step g0 clauses))))

;; case: nested =/or tests (no jump table). Test constants are NOT evaluated —
;; symbols and list constants are quoted; a list in test position is a set (or).
(defmacro case [expr & clauses]
  (let [g (fresh-sym)
        mk-const (fn [c] (if (or (symbol? c) (seq? c)) `(quote ~c) c))
        mk-test (fn [c]
                  (if (seq? c)
                    `(or ~@(map (fn [v] `(= ~g ~(mk-const v))) c))
                    `(= ~g ~(mk-const c))))
        build (fn build [cls]
                (if (empty? cls)
                  nil
                  (if (empty? (rest cls))
                    (first cls)
                    `(if ~(mk-test (first cls)) ~(nth cls 1) ~(build (drop 2 cls))))))]
    `(let* [~g ~expr] ~(build clauses))))
