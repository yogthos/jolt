# deps.edn :tasks (jolt-x4o) + the global gitlibs-style clone cache default
# (jolt-xkd). Tasks are the honest subset of babashka's: a STRING task is a
# shell command; a MAP task carries :main-opts (jolt args) and optional :doc.
# Local-only: no network, no jolt binary — the CLI wrappers stay thin.

(import ../../src/jolt/deps :as deps)

(def base (string (or (os/getenv "TMPDIR") "/tmp") "/jolt-deps-tasks-" (os/time)))
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

(each d ["proj/src" "config"] (mkdirs (string base "/" d)))
(spit (string base "/proj/deps.edn")
  `{:paths ["src"]
    :tasks {clean "rm -rf target"
            test {:doc "run the suite" :main-opts ["-e" "(run-tests)"]}
            fmt {:main-opts ["-e" "(fmt)"]}}}`)
# user-level task, and a project-shadowed name
(spit (string base "/config/deps.edn")
  `{:tasks {lint "echo lint" clean "echo SHADOWED"}}`)

(var fails 0)
(defn check [label got expected]
  (if (= got expected) (print "  ok   " label)
    (do (++ fails) (printf "  FAIL %s: want %q, got %q" label expected got))))

(os/cd (string base "/proj"))
(os/setenv "JOLT_CONFIG" (string base "/config"))

# --- task listing (merged user+project, sorted) ---------------------------------
(def listing (deps/tasks "deps.edn"))
(check "lists all task names"
  (tuple ;(sort (map first listing))) ["clean" "fmt" "lint" "test"])
(check "doc shows in listing"
  (truthy? (some |(and (= (first $) "test") (= (get $ 1) "run the suite")) listing))
  true)

# --- task lookup ------------------------------------------------------------------
(check "string task is shell"
  (deps/task-spec "deps.edn" "clean") {:type :shell :cmd "rm -rf target"})
(check "project task shadows user task"
  (get (deps/task-spec "deps.edn" "clean") :cmd) "rm -rf target")
(check "map task is jolt argv"
  (deps/task-spec "deps.edn" "test") {:type :jolt :argv ["-e" "(run-tests)"]})
(check "user-level task visible"
  (deps/task-spec "deps.edn" "lint") {:type :shell :cmd "echo lint"})
(check "unknown task is nil"
  (deps/task-spec "deps.edn" "nope") nil)

# --- tasks resolve with NO user config (regression: load-config skipped the
# name re-keying when only the project file existed) -----------------------------
(os/setenv "JOLT_CONFIG" (string base "/no-such-dir"))
(check "task works without user config"
  (deps/task-spec "deps.edn" "clean") {:type :shell :cmd "rm -rf target"})
(check "listing works without user config"
  (tuple ;(sort (map first (deps/tasks "deps.edn")))) ["clean" "fmt" "test"])
(os/setenv "JOLT_CONFIG" (string base "/config"))

# --- global clone-tree default (jolt-xkd) ----------------------------------------
# resolution with :local deps never clones, but the default tree dir must come
# from $JOLT_GITLIBS (else (config-dir)/gitlibs), not ./jpm_tree
(os/setenv "JOLT_GITLIBS" (string base "/deep/nested/gitlibs"))
(deps/resolve-deps "deps.edn")
(check "JOLT_GITLIBS dir created (parents too)"
  (truthy? (os/stat (string base "/deep/nested/gitlibs"))) true)
(check "no per-project jpm_tree"   (os/stat (string base "/proj/jpm_tree")) nil)

# roots cache is project-local .cpcache, not inside the clone tree
(deps/resolve-deps-cached "deps.edn")
(check "roots cache in ./.cpcache"
  (truthy? (os/stat (string base "/proj/.cpcache/jolt-deps.jdn"))) true)

(os/setenv "JOLT_GITLIBS" "")
(os/cd "/")
(rmrf base)

(if (> fails 0)
  (error (string "deps-tasks-test: " fails " failing check(s)"))
  (print "\nAll deps-tasks tests passed!"))
