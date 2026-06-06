# `jolt uberscript` bundles a namespace and everything it requires into one .clj
# that runs on a plain jolt with no JOLT_PATH / deps. Runs from source.

(defn- run [env-jolt-path & args]
  (if env-jolt-path (os/setenv "JOLT_PATH" env-jolt-path) (os/setenv "JOLT_PATH" nil))
  (def p (os/spawn ["janet" "src/jolt/main.janet" ;args] :p {:out :pipe :err :pipe}))
  (def out (:read (p :out) :all))
  (os/proc-wait p)
  (string (or out "")))

(defn- mkdirs [p]
  (var acc nil)
  (each seg (filter |(not= "" $) (string/split "/" p))
    (set acc (if (nil? acc) (if (string/has-prefix? "/" p) (string "/" seg) seg) (string acc "/" seg)))
    (unless (os/stat acc) (os/mkdir acc))))
(defn- rmrf [p]
  (when (os/stat p)
    (if (= :directory (os/stat p :mode))
      (do (each e (os/dir p) (rmrf (string p "/" e))) (os/rmdir p))
      (os/rm p))))

(def base (string (or (os/getenv "TMPDIR") "/tmp") "/jolt-uber-" (os/time)))
(rmrf base)
(mkdirs (string base "/proj/src/app"))
(mkdirs (string base "/lib/src/greet"))
(spit (string base "/lib/src/greet/core.clj")
      "(ns greet.core)\n(defn hello [n] (str \"Hello, \" n \"!\"))\n")
(spit (string base "/proj/src/app/core.clj")
      "(ns app.core (:require [greet.core :as g]))\n(defn -main [& args] (println (g/hello (or (first args) \"world\"))))\n")

(var fails 0)
(defn check [label got pred]
  (if (pred got) (print "  ok   " label)
    (do (++ fails) (printf "  FAIL %s: got %q" label got))))
(defn- has [s] (fn [x] (string/find s x)))

(def roots (string base "/proj/src:" base "/lib/src"))
(def out (string base "/out.clj"))

# build the uberscript with the dep roots on JOLT_PATH
(run roots "uberscript" out "-m" "app.core")
(check "uberscript written" (if (os/stat out) "yes" "no") (has "yes"))
(check "bundles the dep ns" (slurp out) (has "(ns greet.core)"))

# run it standalone: no JOLT_PATH, so it only works if the dep was inlined
(check "runs standalone" (run nil out "Bob") (has "Hello, Bob!"))

(rmrf base)
(if (> fails 0)
  (error (string "uberscript-test: " fails " failing check(s)"))
  (print "\nAll uberscript tests passed!"))
