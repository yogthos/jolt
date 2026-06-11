# deps.edn resolution for Jolt.
#
# Resolve git and :local/root dependencies from a deps.edn into a list of source
# directories, which the loader then searches (see evaluator/find-ns-file). We
# reuse jpm's git fetch + cache (jpm/pm) rather than shipping a package manager.
# Maven (:mvn/version) deps are ignored — git only, pure clj/cljc only.
#
# jpm is loaded lazily (require, not import) so it's needed only at resolve time
# (dev/build), never embedded in the shipped binary.

(import ./reader :as reader)

# Read deps.edn with Jolt's reader (not Janet's parse) so EDN `;` line comments
# are handled. It returns plain Janet data — structs with keyword keys, tuples —
# which we walk directly. (#{} sets and tagged literals aren't expected in the
# :deps/:paths we read.)
(defn read-edn [path]
  (when (os/stat path)
    (try (reader/parse-string (slurp path)) ([_] nil))))

(defn- jpm-fn [mod sym]
  (get-in (require mod) [sym :value]))

(defn- ensure-jpm-config [tree]
  ((jpm-fn "jpm/config" 'load-default))
  (setdyn :modpath tree)
  (setdyn :gitpath (dyn :gitpath "git")))

(defn- clone-git [spec]
  # spec is a deps.edn dep value: {:git/url ... :git/sha/:git/tag ...}
  (def resolve-bundle (jpm-fn "jpm/pm" 'resolve-bundle))
  (def download-bundle (jpm-fn "jpm/pm" 'download-bundle))
  (def b (resolve-bundle {:url (get spec :git/url)
                          :sha (get spec :git/sha)
                          :tag (get spec :git/tag)
                          :shallow false}))
  (download-bundle (b :url) (b :type) (b :tag) (b :shallow)))

(defn- src-roots
  "Source dirs of a project/dep at `dir`: its deps.edn :paths joined to dir
  (default [\"src\"])."
  [dir edn]
  (map |(string dir "/" $) (or (and edn (get edn :paths)) ["src"])))

# --- user config + aliases (tools.deps-shaped, scoped to git/:local) -----------

(defn config-dir
  "User-level config dir: $JOLT_CONFIG, else $XDG_CONFIG_HOME/jolt, else
  ~/.jolt — the same fallback chain the Clojure CLI uses for ~/.clojure."
  []
  (or (os/getenv "JOLT_CONFIG")
      (when-let [x (os/getenv "XDG_CONFIG_HOME")]
        (when (> (length x) 0) (string x "/jolt")))
      (string (os/getenv "HOME") "/.jolt")))

(defn- merge-per-key [a b]  # dictionary union, b's entries win
  (def out @{})
  (each m [a b] (when (dictionary? m) (eachp [k v] m (put out k v))))
  out)

(defn load-config
  "The project deps.edn merged over the user-level one (config-dir)/deps.edn.
  tools.deps merge semantics: scalar keys and :paths replace (project wins),
  :deps and :aliases merge per key with the project winning. Relative
  :local/root in the USER file is resolved against the cwd — prefer absolute
  paths there."
  [deps-edn-path]
  (def proj (read-edn deps-edn-path))
  (def user (read-edn (string (config-dir) "/deps.edn")))
  (cond
    (nil? user) proj
    (nil? proj) user
    (let [out (merge-per-key user proj)]
      (put out :deps (merge-per-key (get user :deps) (get proj :deps)))
      (put out :aliases (merge-per-key (get user :aliases) (get proj :aliases)))
      out)))

(defn combine-aliases
  "Combine the selected alias keywords against `edn`'s :aliases:
  :extra-paths and :extra-deps accumulate in order, :main-opts is last-wins
  (the tools.deps CLI rules). Unknown alias -> error."
  [edn aliases]
  (def als (or (and (dictionary? edn) (get edn :aliases)) {}))
  (def extra-paths @[])
  (def extra-deps @{})
  (var main-opts nil)
  (each a (or aliases [])
    (def spec (get als a))
    (when (nil? spec) (error (string "unknown alias: " a)))
    (each p (or (get spec :extra-paths) []) (array/push extra-paths p))
    (when (dictionary? (get spec :extra-deps))
      (eachp [lib coord] (get spec :extra-deps) (put extra-deps lib coord)))
    (when-let [mo (get spec :main-opts)]
      (set main-opts (tuple ;(map string mo)))))
  {:extra-paths extra-paths :extra-deps extra-deps :main-opts main-opts})

(defn alias-main-opts
  "The :main-opts the selected aliases produce (last alias with the key wins),
  or nil. Reads the merged user+project config."
  [deps-edn-path aliases]
  (get (combine-aliases (load-config deps-edn-path) aliases) :main-opts))

(defn resolve-deps
  "Resolve the git/:local deps of `deps-edn-path` into an ordered, de-duplicated
  array of source dirs (the project's own :paths first, then each dependency's,
  transitively). `tree` is where jpm's clone cache lives (default ./jpm_tree).
  `aliases` (keywords) pull :extra-paths/:extra-deps from the merged config's
  :aliases. The user-level deps.edn (see load-config) merges under the project."
  [deps-edn-path &opt tree aliases]
  (default tree (string (os/cwd) "/jpm_tree"))
  (os/mkdir tree)
  (ensure-jpm-config tree)
  (def edn (load-config deps-edn-path))
  (def extra (combine-aliases edn aliases))
  (def roots @[])
  (def seen @{})   # lib name -> chosen coordinate (for conflict reporting)
  (defn add-root [r] (unless (index-of r roots) (array/push roots r)))
  # Reader symbols carry position metadata, so dedup/conflict keys must use the
  # NAME, never (string lib) — two my/b symbols from different files differ.
  (defn lib-name [lib]
    (if (and (dictionary? lib) (get lib :name))
      (if-let [ns (get lib :ns)]
        (string ns "/" (get lib :name))
        (get lib :name))
      (string lib)))
  (defn coord-str [spec]
    (cond
      (and (dictionary? spec) (get spec :local/root))
        (string ":local/root " (get spec :local/root))
      (and (dictionary? spec) (get spec :git/url))
        (string (get spec :git/url) " @ " (or (get spec :git/sha) (get spec :git/tag)))
      (string/format "%j" spec)))
  (defn coord= [a b]
    (and (deep= (get a :local/root) (get b :local/root))
         (deep= (get a :git/url) (get b :git/url))
         (deep= (get a :git/sha) (get b :git/sha))
         (deep= (get a :git/tag) (get b :git/tag))))
  (def queue @[])
  (defn discover [lib spec base-dir]
    (def k (lib-name lib))
    (if-let [prev (get seen k)]
      (unless (coord= prev spec)
        (eprintf "WARNING: %s: conflicting coordinates — using %s, ignoring %s"
                 k (coord-str prev) (coord-str spec)))
      (do
        (put seen k spec)
        (def dir
          (cond
            (and (dictionary? spec) (get spec :git/url)) (clone-git spec)
            (and (dictionary? spec) (get spec :local/root))
              (let [lr (get spec :local/root)]
                (if (string/has-prefix? "/" lr) lr (string base-dir "/" lr)))
            nil))  # :mvn/* and anything else: skip
        (when dir
          (def dep-edn (read-edn (string dir "/deps.edn")))
          (each r (src-roots dir dep-edn) (add-root r))
          (array/push queue [dep-edn dir])))))
  # the project's own paths (+ alias extra paths) lead the roots
  (each r (src-roots (os/cwd) edn) (add-root r))
  (each pp (extra :extra-paths) (add-root (string (os/cwd) "/" pp)))
  # breadth-first: every top-level dep (incl. alias :extra-deps) registers
  # before any transitive dep — so a top-level coordinate always wins,
  # matching tools.deps
  (eachp [lib spec] (or (and (dictionary? edn) (get edn :deps)) {})
    (discover lib spec (os/cwd)))
  (eachp [lib spec] (extra :extra-deps)
    (discover lib spec (os/cwd)))
  (while (> (length queue) 0)
    (def [dep-edn dir] (get queue 0))
    (array/remove queue 0)
    (when (dictionary? dep-edn)
      (eachp [lib spec] (or (get dep-edn :deps) {})
        (discover lib spec dir))))
  roots)

(defn resolve-deps-cached
  "Like resolve-deps, but caches the resolved roots in the tree keyed on a hash
  of the project deps.edn + the user deps.edn + the selected aliases, so an
  unchanged config resolves without re-fetching."
  [deps-edn-path &opt tree aliases]
  (default tree (string (os/cwd) "/jpm_tree"))
  (when (os/stat deps-edn-path)
    (os/mkdir tree)
    (def cache-file (string tree "/.jolt-deps-roots.jdn"))
    (def user-path (string (config-dir) "/deps.edn"))
    (def h (hash [(slurp deps-edn-path)
                  (when (os/stat user-path) (slurp user-path))
                  (string/format "%j" (map string (or aliases [])))]))
    (def cached (when (os/stat cache-file) (try (parse (slurp cache-file)) ([_] nil))))
    (if (and cached (= h (get cached :hash)))
      (get cached :roots)
      (let [roots (resolve-deps deps-edn-path tree aliases)]
        (spit cache-file (string/format "%j" {:hash h :roots roots}))
        roots))))
