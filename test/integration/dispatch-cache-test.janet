# Protocol host-value dispatch cache (jolt-4ay).
#
# Host-value protocol dispatch used to recompute the candidate type-tag list and
# walk the registry on every call. It's now a generation-guarded cache keyed by
# (most-specific-host-tag, protocol, method); registering a protocol impl bumps
# the registry generation and invalidates it. This pins correctness: the cache
# must never hide a re-extension.

(use ../../src/jolt/api)

(var failures 0)
(defn- check [label got want]
  (unless (= got want)
    (++ failures)
    (printf "FAIL [%s] got %q want %q" label got want)))

(each mode [{:compile? true} {} {:aot-core? false}]
  (def ctx (init mode))
  (eval-string ctx "(defprotocol P (m [x]))")
  (eval-string ctx "(extend-protocol P Number (m [x] (* x 2)))")
  (check (string mode " host dispatch") (eval-string ctx "(m 5)") 10)
  (check (string mode " cache hit (same class)") (eval-string ctx "(m 7)") 14)
  # Re-extend: registry generation bumps, cache must invalidate.
  (eval-string ctx "(extend-protocol P Number (m [x] (+ x 100)))")
  (check (string mode " sees re-extension") (eval-string ctx "(m 5)") 105)
  # Extending a different host class bumps gen too; number impl re-resolves.
  (eval-string ctx "(extend-protocol P String (m [x] (str \"s:\" x)))")
  (check (string mode " other class") (eval-string ctx "(m \"hi\")") "s:hi")
  (check (string mode " number after other-class extend") (eval-string ctx "(m 3)") 103))

(if (pos? failures)
  (do (printf "dispatch-cache: %d failure(s)" failures) (os/exit 1))
  (print "dispatch-cache: all cases passed (compile, interpret, aot-core off)"))
