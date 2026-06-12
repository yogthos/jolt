# deps.edn resolution into source roots, then loading a library through them.
# Uses :local/root deps only so it needs no network (the git path is the same
# code, exercised manually against real repos).

(use ../../src/jolt/api)
(use ../../src/jolt/types)
(import ../../src/jolt/deps :as deps)

# Captured before any os/cd: subprocess tests below re-import src/jolt/deps.
(def repo-root (os/cwd))

(def base (string (or (os/getenv "TMPDIR") "/tmp") "/jolt-deps-resolve-" (os/time)))
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

# project -> depends on lib-a (local), which depends on lib-b (local, transitive)
(each d ["proj/src" "a/src/liba" "b/src/libb"] (mkdirs (string base "/" d)))
(spit (string base "/proj/deps.edn") `{:paths ["src"] :deps {my/a {:local/root "../a"}}}`)
(spit (string base "/a/deps.edn") `{:paths ["src"] :deps {my/b {:local/root "../b"}}}`)
(spit (string base "/b/deps.edn") `{:paths ["src"]}`)
(spit (string base "/a/src/liba/core.clj") "(ns liba.core (:require [libb.core :as b]))\n(defn val [] (b/n))\n")
(spit (string base "/b/src/libb/core.clj") "(ns libb.core)\n(defn n [] 99)\n")

(var fails 0)
(defn check [label got expected]
  (if (= got expected) (print "  ok   " label)
    (do (++ fails) (printf "  FAIL %s: want %q, got %q" label expected got))))

(os/cd (string base "/proj"))
(def roots (deps/resolve-deps "deps.edn" (string base "/proj/jpm_tree")))
# roots: proj/src, a/src (transitive: b/src) — at least the two dep srcs present
(check "resolves transitive local dep roots"
  (truthy? (and (some |(string/has-suffix? "/a/src" $) roots)
                (some |(string/has-suffix? "/b/src" $) roots)))
  true)

# load through the resolved roots: liba.core requires libb.core transitively
(def ctx (init {:paths roots}))
(ctx-set-current-ns ctx "user")
(let [r (protect (eval-string ctx "(do (require (quote [liba.core :as a])) (a/val))"))]
  (check "require local lib + transitive dep" (if (r 0) (r 1) (string "ERR " (r 1))) 99))

# cached resolution returns the same roots without re-walking
(check "cached resolve matches"
  (deep= roots (deps/resolve-deps-cached "deps.edn" (string base "/proj/jpm_tree")))
  true)

# The cache must hit across PROCESSES: janet's (hash ...) is seeded per process,
# so a key built with it never matches a cached one and every invocation
# re-resolved (and re-fetched git deps). Detection: plant a sentinel root in the
# cache file — a fresh process that hits the cache returns it; a process that
# misses re-resolves and overwrites it.
(os/cd (string base "/proj"))
(def cache-file ".cpcache/jolt-deps.jdn")
(def cached-now (parse (slurp cache-file)))
(spit cache-file
  (string/format "%j" (merge cached-now
                             {:roots [;(get cached-now :roots) "/SENTINEL"]})))
(defn subprocess-roots []
  (def code
    (string `(os/cd "` repo-root `") `
            `(import ./src/jolt/deps :as deps) `
            `(os/cd "` base "/proj" `") `
            `(print (string/join (deps/resolve-deps-cached "deps.edn" "` base "/proj/jpm_tree" `") ":"))`))
  (def p (os/spawn ["janet" "-e" code] :px {:out :pipe}))
  (def out (ev/read (p :out) :all))
  (os/proc-wait p)
  (string/trim (string out)))
(check "cache hits across processes"
  (string/has-suffix? "/SENTINEL" (subprocess-roots))
  true)

(os/cd "/")
(rmrf base)

# Git-dep resolution must keep stdout clean: `JOLT_PATH=$(jolt-deps path)` is
# the documented capture, and git's checkout chatter ("HEAD is now at …") was
# corrupting it. Uses a file:// git dep so no network is needed.
(def gbase (string (or (os/getenv "TMPDIR") "/tmp") "/jolt-deps-gitout-" (os/time)))
(rmrf gbase)
(each d ["lib/src/glib" "proj2"] (mkdirs (string gbase "/" d)))
(spit (string gbase "/lib/src/glib/core.clj") "(ns glib.core)\n(defn n [] 7)\n")
(spit (string gbase "/lib/deps.edn") `{:paths ["src"]}`)
(defn sh-out [args &opt cwd]
  (def p (os/spawn args :px {:out :pipe :err :pipe :cd (or cwd ".")}))
  (def out (ev/read (p :out) :all))
  (os/proc-wait p)
  (string/trim (string out)))
(def git-ok
  (truthy?
    (protect
      (do (sh-out ["git" "-c" "init.defaultBranch=master" "init"] (string gbase "/lib"))
          (sh-out ["git" "add" "-A"] (string gbase "/lib"))
          (sh-out ["git" "-c" "user.email=t@t" "-c" "user.name=t" "commit" "-m" "init" "-q"]
                  (string gbase "/lib"))))))
(if (not git-ok)
  (print "  skip git-dep stdout test (git unavailable)")
  (do
    (def sha (sh-out ["git" "rev-parse" "HEAD"] (string gbase "/lib")))
    (spit (string gbase "/proj2/deps.edn")
      (string `{:paths ["src"] :deps {my/glib {:git/url "file://` gbase `/lib" :git/sha "` sha `"}}}`))
    (os/setenv "JOLT_GITLIBS" (string gbase "/gitlibs"))
    (def code
      (string `(os/cd "` repo-root `") `
              `(import ./src/jolt/deps :as deps) `
              `(os/cd "` gbase "/proj2" `") `
              `(deps/resolve-deps "deps.edn" "` gbase "/proj2/jpm_tree" `") `
              `(eprint "done")`))
    (def p (os/spawn ["janet" "-e" code] :px {:out :pipe}))
    (def out (ev/read (p :out) :all))
    (os/proc-wait p)
    (os/setenv "JOLT_GITLIBS" nil)
    (check "git-dep resolution keeps stdout clean" (string (or out "")) ""))
  )
(rmrf gbase)

# --- :jpm/module deps: janet libraries installed through jpm -----------------
# Verification only (jpm owns installation): an importable module passes and
# contributes no roots; a missing one errors with the install hint. jpm/pm is
# always importable wherever jpm itself runs (CI included).
(do
  (def jbase (string (or (os/getenv "TMPDIR") "/tmp") "/jolt-deps-jpm-" (os/time)))
  (mkdirs (string jbase "/src"))
  (spit (string jbase "/deps.edn")
    `{:paths ["src"] :deps {janet/jpm-pm {:jpm/module "jpm/pm"}}}`)
  (def cwd (os/cwd))
  (os/cd jbase)
  (def roots (deps/resolve-deps "deps.edn" (string jbase "/jpm_tree")))
  (os/cd cwd)
  (check "jpm module dep resolves" true (not (nil? roots)))
  (check "jpm module contributes no roots" 1 (length roots))

  (spit (string jbase "/deps.edn")
    `{:paths ["src"] :deps {janet/nope {:jpm/module "no/such-module-xyz"}}}`)
  (os/cd jbase)
  (def r (protect (deps/resolve-deps "deps.edn" (string jbase "/jpm_tree"))))
  (os/cd cwd)
  (check "missing jpm module errors" false (r 0))
  (check "error carries the install hint" true
         (not (nil? (string/find "jpm install" (string (r 1))))))
  (rmrf jbase))

(if (> fails 0)
  (error (string "deps-resolve-test: " fails " failing check(s)"))
  (print "\nAll deps-resolve tests passed!"))
