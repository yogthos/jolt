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
