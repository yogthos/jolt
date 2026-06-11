# yogthos/config acceptance: load the real library from ~/src/config and run
# its whole surface — PushbackReader over io/reader, edn/read from a reader,
# Long/parseLong + BigInteger. + Boolean/parseBoolean, System/getenv +
# System/getProperties as iterable maps, str->value, keywordize, deep-merge,
# and the defonce env built at load. SKIPS cleanly when the checkout is
# absent (CI); the shim surface itself is covered by host-interop-spec.

(import ../../src/jolt/api :as api)
(use ../../src/jolt/reader)

(def config-src (string (os/getenv "HOME") "/src/config/src"))

(if (nil? (os/stat (string config-src "/config/core.clj")))
  (print "config-lib-test: ~/src/config not present, skipping")
  (do
    (reader-features-set! ["jolt" "clj" "default"])

    # run from a temp project dir so config.edn/.lein-env are controlled
    (def base (string (or (os/getenv "TMPDIR") "/tmp") "/jolt-config-lib-" (os/time)))
    (defn rmrf [p]
      (when (os/stat p)
        (if (= :directory (os/stat p :mode))
          (do (each e (os/dir p) (rmrf (string p "/" e))) (os/rmdir p))
          (os/rm p))))
    (rmrf base)
    (os/mkdir base)
    (spit (string base "/config.edn")
      "{:db {:host \"localhost\"\n       :port 5432}\n :app-name \"demo\"}\n")
    (spit (string base "/.lein-env") "{:db {:port 9999}}")
    (os/cd base)
    (os/setenv "CONFIG_TEST_NUM" "42")
    (os/setenv "CONFIG_TEST_FLAG" "true")
    (os/setenv "CONFIG_TEST_EDN" "{:x 1}")

    (def ctx (api/init {:paths [config-src]}))

    (print "loading config.core (defonce env runs load-env at require)...")
    (api/eval-string ctx "(require (quote [config.core :as cfg]))")
    (print "  ok")

    (var fails 0)
    (defn check [label expr expected]
      (def r (protect (api/eval-string ctx expr)))
      (def got (if (r 0) (r 1) (string "ERR " (r 1))))
      (if (deep= got expected) (print "  ok   " label)
        (do (++ fails) (printf "  FAIL %s: want %q, got %q" label expected got))))

    (print "config.edn + .lein-env deep merge...")
    (check "nested value from config.edn" "(get-in cfg/env [:db :host])" "localhost")
    (check ".lein-env overrides nested"   "(get-in cfg/env [:db :port])" 9999)
    (check "top-level value"              "(:app-name cfg/env)" "demo")
    (print "env vars keywordized + converted...")
    (check "numeric env var is a number"  "(:config-test-num cfg/env)" 42)
    (check "boolean env var"              "(:config-test-flag cfg/env)" true)
    (check "edn env var parses"           "(= {:x 1} (:config-test-edn cfg/env))" true)
    (print "library fns directly...")
    (check "str->value number"            "(cfg/str->value \"17\")" 17)
    (check "str->value bool"              "(cfg/str->value \"false\")" false)
    (check "str->value word"              "(cfg/str->value \"hello\")" "hello")
    (check "str->value edn vec"           "(= [1 2] (cfg/str->value \"[1 2]\"))" true)
    (check "str->value symbol stays str"  "(cfg/str->value \"foo/bar\")" "foo/bar")
    (check "keywordize"                   "(cfg/keywordize \"FOO_BAR__BAZ_QMARK_\")" :foo-bar/baz?)
    (check "read-config-file"             "(get-in (cfg/read-config-file \"config.edn\") [:db :port])" 5432)
    (check "deep-merge-with"
      "(= {:a {:b 3}} (cfg/deep-merge-with + {:a {:b 1}} {:a {:b 2}}))" true)
    (print "reload-env...")
    (check "reload-env returns merged map"
      "(do (cfg/reload-env) (get-in cfg/env [:db :host]))" "localhost")

    (os/cd "/")
    (rmrf base)

    (if (> fails 0)
      (error (string "config-lib-test: " fails " failing check(s)"))
      (print "\nconfig-lib-test: all passed"))))
