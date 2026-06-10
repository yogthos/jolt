# init-cached: disk-cached AOT image of the fully-built context.
#
# init in compile mode costs ~2.4 s (tier loading, analyzer self-compile, macro
# recompilation). init-cached pays that once, marshals the built ctx to an image
# file (the same machinery as api/snapshot), and every later process unmarshals
# it instead of rebuilding. The cache key fingerprints the embedded .clj stdlib,
# the .janet seed sources, and the init opts, so any source change invalidates.
#
# The cross-process case is the one that matters (each `jpm test` file is its
# own janet process), so the warm-load checks run in a SUBPROCESS against the
# image this process bakes.
(use ../../src/jolt/api)

(print "ctx image cache...")

(def dir (string (or (os/getenv "TMPDIR") "/tmp") "/jolt-img-test-" (os/getpid)))
(os/mkdir dir)
(os/setenv "JOLT_IMAGE_CACHE_DIR" dir)
# The cache is the test subject — undo an ambient opt-out (and for the subprocess).
(os/setenv "JOLT_NO_IMAGE_CACHE" nil)
(defer (do (each f (os/dir dir) (os/rm (string dir "/" f))) (os/rmdir dir))

  # 1. Cold init: builds the ctx, writes an image, and is fully functional.
  (def t0 (os/clock))
  (def ctx1 (init-cached {:compile? true}))
  (def cold-s (- (os/clock) t0))
  (assert (= 3 (eval-string ctx1 "(+ 1 2)")) "cold ctx evaluates")
  (def files (filter |(string/has-suffix? ".jimg" $) (os/dir dir)))
  (assert (= 1 (length files)) (string "one image written, got " (length files)))

  # 2. Warm init in THIS process: loads the image, functional, and much faster.
  (def t1 (os/clock))
  (def ctx2 (init-cached {:compile? true}))
  (def warm-s (- (os/clock) t1))
  (assert (= 10 (eval-string ctx2 "(do (defn f [x] (* 2 x)) (f 5))")) "warm ctx compiles defns")
  (assert (< warm-s (/ cold-s 4))
          (string/format "warm load (%.0f ms) at least 4x faster than cold (%.0f ms)"
                         (* 1000 warm-s) (* 1000 cold-s)))

  # 3. Different opts get a different image (no false sharing between modes).
  (init-cached {})
  (def files2 (filter |(string/has-suffix? ".jimg" $) (os/dir dir)))
  (assert (= 2 (length files2)) "interpret-mode image is keyed separately")

  # 4. Cross-process warm load: a fresh janet process loads the image this
  #    process baked and runs real work — compiled defns, redefinition,
  #    macros, lazy seqs, protocols, multimethods, stdlib require.
  (def checks
    ``(use ./src/jolt/api)
      (def t0 (os/clock))
      (def ctx (init-cached {:compile? true}))
      (def warm-ms (* 1000 (- (os/clock) t0)))
      (def img-files (filter |(string/has-suffix? ".jimg" $)
                             (os/dir (os/getenv "JOLT_IMAGE_CACHE_DIR"))))
      (assert (= 2 (length img-files)) "subprocess hit the cache (no new image)")
      (assert (= 3 (eval-string ctx "(+ 1 2)")) "arith")
      (assert (= 120 (eval-string ctx "(do (defn fact [n] (if (zero? n) 1 (* n (fact (dec n))))) (fact 5))")) "compiled defn")
      (assert (= 7 (eval-string ctx "(do (def a 3) (def a 7) a)")) "redefinition")
      (assert (= 6 (eval-string ctx "(-> 1 inc (* 3))")) "macros expand")
      (assert (= 9 (eval-string ctx "(do (defmacro tw [x] `(* 3 ~x)) (tw 3))")) "defmacro works post-load")
      (assert (= [2 4 6] (normalize-pvecs (eval-string ctx "(vec (map #(* 2 %) [1 2 3]))"))) "lazy/HOF")
      (assert (= "a-b" (eval-string ctx "(do (require '[clojure.string :as str]) (str/join \"-\" [\"a\" \"b\"]))")) "stdlib require")
      (assert (= 42 (eval-string ctx "(do (defprotocol P (pf [x])) (defrecord R [] P (pf [x] 42)) (pf (->R)))")) "protocols")
      (assert (= :big (eval-string ctx "(do (defmulti m (fn [x] (if (> x 5) :big :small))) (defmethod m :big [_] :big) (m 10))")) "multimethods")
      (print "subprocess warm load ok in " (math/round warm-ms) " ms")``)
  (def code (os/execute ["janet" "-e" checks] :p))
  (assert (= 0 code) "cross-process warm load passes")

  # 5. A source change invalidates: poisoning the fingerprint env knob is not
  #    possible from here, but a corrupted image must fall back to a rebuild
  #    rather than crash.
  (each f (os/dir dir)
    (when (string/has-suffix? ".jimg" f) (spit (string dir "/" f) "garbage")))
  (def ctx3 (init-cached {:compile? true}))
  (assert (= 3 (eval-string ctx3 "(+ 1 2)")) "corrupted image falls back to rebuild")

  (printf "ctx image cache passed! (cold %.0f ms, warm %.0f ms)"
          (* 1000 cold-s) (* 1000 warm-s)))
