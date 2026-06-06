# Specification: jolt.nrepl bencode codec (pure, no networking).
# The server/client wire behavior is covered by test/integration/nrepl-test.janet.
(use ../support/harness)

(defn- b [body]
  (string "(do (require '[jolt.nrepl :as nr]) " body ")"))
(defn- rt [body]
  # round-trip a value through encode -> decode
  (b (string "(nr/decode (nr/reader nil (nr/encode " body ")))")))

(defspec "jolt.nrepl / bencode round-trip"
  ["integer"        "42"            (rt "42")]
  ["negative"       "-7"            (rt "-7")]
  ["string"         "\"hello\""     (rt "\"hello\"")]
  ["empty string"   "\"\""          (rt "\"\"")]
  ["list"           "[\"a\" 1 \"b\"]" (rt "[\"a\" 1 \"b\"]")]
  ["nested list"    "[1 [2 3]]"     (rt "[1 [2 3]]")]
  ["dict"           "{\"op\" \"eval\" \"id\" \"7\"}" (rt "{\"op\" \"eval\" \"id\" \"7\"}")]
  ["dict with list" "{\"status\" [\"done\"]}"        (rt "{\"status\" [\"done\"]}")]
  ["nested dict"    "{\"a\" {\"b\" 1}}"              (rt "{\"a\" {\"b\" 1}}")])

(defspec "jolt.nrepl / bencode encode shape"
  ["int"    "\"i42e\""   (b "(nr/encode 42)")]
  ["string" "\"5:hello\"" (b "(nr/encode \"hello\")")]
  ["list"   "\"li1ei2ee\"" (b "(nr/encode [1 2])")]
  # dict keys are sorted lexicographically
  ["dict sorted keys" "\"d1:ai1e1:bi2ee\"" (b "(nr/encode {\"b\" 2 \"a\" 1})")])
