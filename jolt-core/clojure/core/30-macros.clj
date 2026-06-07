;; clojure.core — macro tier. Macros expressed in Clojure (defmacro + syntax-quote)
;; rather than as hand-built Janet form-transformers. Loaded after the fn tiers,
;; so a macro here may use any already-frozen core fn/macro.
;;
;; IMPORTANT — only macros NOT used by the self-hosted compiler (jolt-core/jolt/*)
;; or by the earlier overlay tiers belong here; those (and/or/when/when-not/
;; when-let/cond/case/doseq/declare/cond->/->) must stay available before this
;; tier loads, so they remain in Janet for now. Everything here is user-facing.
;;
;; Migration: remove the Janet core-X macro fn AND its core-macro-names entry when
;; moving a macro here (defmacro installs the :macro flag itself).

(defmacro comment [& body] nil)

;; Single arglist (Jolt defmacro is single-arity); the optional else defaults nil
;; via rest-destructuring.
(defmacro if-not [test then & [else]]
  `(if (not ~test) ~then ~else))
