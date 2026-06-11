# deps.edn aliases + user-level config merge (jolt-4go).
#
# Mirrors tools.deps semantics scoped to what jolt supports (git/:local, no
# maven): :aliases with :extra-paths / :extra-deps / :main-opts selected by
# keyword; a user deps.edn (under $JOLT_CONFIG, else $XDG_CONFIG_HOME/jolt,
# else ~/.jolt) merged UNDER the project file — :deps and :aliases merge per
# key with the project winning, :paths replaces. Local deps only: no network.

(import ../../src/jolt/deps :as deps)

(def base (string (or (os/getenv "TMPDIR") "/tmp") "/jolt-deps-aliases-" (os/time)))
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

(each d ["proj/src" "proj/dev" "proj/test" "a/src" "c/src" "u/src" "config"]
  (mkdirs (string base "/" d)))

# project: src + dep a; :dev alias adds dev/ + dep c; :test alias adds test/
(spit (string base "/proj/deps.edn")
  `{:paths ["src"]
    :deps {my/a {:local/root "../a"}}
    :aliases {:dev {:extra-paths ["dev"]
                    :extra-deps {my/c {:local/root "../c"}}}
              :test {:extra-paths ["test"]
                     :main-opts ["-e" "(run-tests)"]}
              :bench {:main-opts ["-e" "(bench)"]}}}`)
(spit (string base "/a/deps.edn") `{:paths ["src"]}`)
(spit (string base "/c/deps.edn") `{:paths ["src"]}`)
(spit (string base "/u/deps.edn") `{:paths ["src"]}`)

# user-level config: a :user-tool alias the project file doesn't have, plus a
# :dev alias that the PROJECT's :dev must shadow (per-key merge, project wins)
(spit (string base "/config/deps.edn")
  `{:aliases {:user-tool {:extra-deps {my/u {:local/root "BASE/u"}}}
              :dev {:extra-paths ["should-not-win"]}}}`)
# :local/root in the user file is relative to... nothing useful; use absolute
(spit (string base "/config/deps.edn")
  (string/replace "BASE" base (slurp (string base "/config/deps.edn"))))

(var fails 0)
(defn check [label got expected]
  (if (= got expected) (print "  ok   " label)
    (do (++ fails) (printf "  FAIL %s: want %q, got %q" label expected got))))
(defn has-suffix-root [roots suff]
  (truthy? (some |(string/has-suffix? suff $) roots)))

(os/cd (string base "/proj"))
(os/setenv "JOLT_CONFIG" (string base "/config"))
(def tree (string base "/proj/jpm_tree"))

# --- no aliases: plain resolution, dev/test/c absent ---------------------------
(def plain (deps/resolve-deps "deps.edn" tree))
(check "plain: project src present"   (has-suffix-root plain "/proj/src") true)
(check "plain: dep a present"         (has-suffix-root plain "/a/src") true)
(check "plain: alias path absent"     (has-suffix-root plain "/proj/dev") false)
(check "plain: alias dep absent"      (has-suffix-root plain "/c/src") false)

# --- :dev alias: extra-paths + extra-deps --------------------------------------
(def dev (deps/resolve-deps "deps.edn" tree [:dev]))
(check "dev: extra path present"      (has-suffix-root dev "/proj/dev") true)
(check "dev: extra dep present"       (has-suffix-root dev "/c/src") true)
(check "dev: base dep still present"  (has-suffix-root dev "/a/src") true)
(check "dev: project :dev shadows user :dev"
  (has-suffix-root dev "/proj/should-not-win") false)

# --- multiple aliases combine ---------------------------------------------------
(def both (deps/resolve-deps "deps.edn" tree [:dev :test]))
(check "multi: both extra paths"
  (and (has-suffix-root both "/proj/dev") (has-suffix-root both "/proj/test")) true)

# --- alias from the USER deps.edn ----------------------------------------------
(def ut (deps/resolve-deps "deps.edn" tree [:user-tool]))
(check "user alias resolves its dep"  (has-suffix-root ut "/u/src") true)

# --- main-opts: from alias, last alias wins ------------------------------------
(check "main-opts from alias"
  (deps/alias-main-opts "deps.edn" [:test]) ["-e" "(run-tests)"])
(check "main-opts last alias wins"
  (deps/alias-main-opts "deps.edn" [:test :bench]) ["-e" "(bench)"])
(check "main-opts absent is nil"
  (deps/alias-main-opts "deps.edn" [:dev]) nil)

# --- cached resolution keys on aliases + user config ----------------------------
(check "cache: aliased result differs from plain"
  (deep= (deps/resolve-deps-cached "deps.edn" tree)
         (deps/resolve-deps-cached "deps.edn" tree [:dev]))
  false)
(check "cache: same key returns same roots"
  (deep= (deps/resolve-deps-cached "deps.edn" tree [:dev])
         (deps/resolve-deps-cached "deps.edn" tree [:dev]))
  true)

# --- unknown alias errors --------------------------------------------------------
(check "unknown alias errors"
  (let [r (protect (deps/resolve-deps "deps.edn" tree [:nope]))] (r 0))
  false)

# --- works without a user config (env unset) ------------------------------------
(os/setenv "JOLT_CONFIG" (string base "/no-such-dir"))
(check "no user config still resolves"
  (has-suffix-root (deps/resolve-deps "deps.edn" tree) "/a/src") true)

(os/cd "/")
(rmrf base)

(if (> fails 0)
  (error (string "deps-aliases-test: " fails " failing check(s)"))
  (print "\nAll deps-aliases tests passed!"))
