# deps.edn conflict semantics (jolt-42f), tools.deps-shaped:
# a TOP-LEVEL :deps entry beats any transitive coordinate for the same lib
# (resolution is breadth-first, top level enqueued first), and when two
# DIFFERENT coordinates for one lib meet, a warning naming both goes to stderr.
# Local deps only: no network.

(import ../../src/jolt/deps :as deps)

(def base (string (or (os/getenv "TMPDIR") "/tmp") "/jolt-deps-conflicts-" (os/time)))
(defn rmrf [p]
  (when (os/stat p)
    (if (= :directory (os/stat p :mode))
      (do (each e (os/dir p) (rmrf (string p "/" e))) (os/rmdir p))
      (os/rm p))))
(rmrf base)
(defn mkdirs [p]
  (def abs (string/has-prefix? "/" p))
  (var acc nil)
  (each seg (filter |(not= "" $) (string/split "/" p))
    (set acc (cond (nil? acc) (if abs (string "/" seg) seg) (string acc "/" seg)))
    (unless (os/stat acc) (os/mkdir acc))))

# proj depends on A and on B@b2 (top level). A depends on B@b1 (transitive).
# DFS-first-wins would pick b1; tools.deps semantics pick the top-level b2.
(each d ["proj/src" "a/src" "b1/src" "b2/src"] (mkdirs (string base "/" d)))
(spit (string base "/proj/deps.edn")
  `{:paths ["src"]
    :deps {my/a {:local/root "../a"}
           my/b {:local/root "../b2"}}}`)
(spit (string base "/a/deps.edn")
  `{:paths ["src"] :deps {my/b {:local/root "../b1"}}}`)
(spit (string base "/b1/deps.edn") `{:paths ["src"]}`)
(spit (string base "/b2/deps.edn") `{:paths ["src"]}`)

(var fails 0)
(defn check [label got expected]
  (if (= got expected) (print "  ok   " label)
    (do (++ fails) (printf "  FAIL %s: want %q, got %q" label expected got))))
(defn has-suffix-root [roots suff]
  (truthy? (some |(string/has-suffix? suff $) roots)))

(os/cd (string base "/proj"))
(def tree (string base "/proj/jpm_tree"))

(def warn-buf @"")
(def roots (with-dyns [:err warn-buf] (deps/resolve-deps "deps.edn" tree)))

(check "top-level coordinate wins"    (has-suffix-root roots "/b2/src") true)
(check "transitive loser not on path" (has-suffix-root roots "/b1/src") false)
(check "dep a still resolved"         (has-suffix-root roots "/a/src") true)
(check "conflict warning names the lib"
  (truthy? (string/find "my/b" (string warn-buf))) true)
(check "conflict warning names both coordinates"
  (and (truthy? (string/find "../b1" (string warn-buf)))
       (truthy? (string/find "../b2" (string warn-buf)))) true)

# same coordinate twice from different parents: no warning
(spit (string base "/a/deps.edn")
  `{:paths ["src"] :deps {my/b {:local/root "../b2"}}}`)
(def warn2 @"")
(with-dyns [:err warn2] (deps/resolve-deps "deps.edn" tree))
(check "agreeing coordinates warn nothing" (string warn2) "")

(os/cd "/")
(rmrf base)

(if (> fails 0)
  (error (string "deps-conflicts-test: " fails " failing check(s)"))
  (print "\nAll deps-conflicts tests passed!"))
