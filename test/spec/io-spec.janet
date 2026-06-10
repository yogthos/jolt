# Specification: printing / output (print/println/pr/prn, *-str, format, str).
# Output is captured with with-out-str (jolt-rfw); the *-str fns return strings.
(use ../support/harness)

(defspec "io / with-out-str captures"
  ["println"         "\"hi\\n\""   "(with-out-str (println \"hi\"))"]
  ["print spaces"    "\"a b\""     "(with-out-str (print \"a\" \"b\"))"]
  ["prn quotes"      "\"[1 2]\\n\"" "(with-out-str (prn [1 2]))"]
  ["pr no newline"   "\"5\""       "(with-out-str (pr 5))"]
  ["multiple writes" "\"12\""      "(with-out-str (print 1) (print 2))"]
  ["no output"       "\"\""        "(with-out-str 42)"]
  ["println no args" "\"\\n\""     "(with-out-str (println))"])

(defspec "io / *-str builders"
  ["print-str"       "\"a b\""     "(print-str \"a\" \"b\")"]
  ["println-str"     "\"x\\n\""    "(println-str \"x\")"]
  ["prn-str"         "\"[1 2]\\n\"" "(prn-str [1 2])"]
  ["pr-str quotes"   "\"\\\"s\\\"\"" "(pr-str \"s\")"]
  ["pr-str keyword"  "\":a\""      "(pr-str :a)"])

(defspec "io / str & format"
  ["str concat"      "\"1:ab\""    "(str 1 :a \"b\")"]
  ["str nil"         "\"\""        "(str nil)"]
  ["str of coll"     "\"[1 2]\""   "(str [1 2])"]
  ["format d/s"      "\"5-x\""     "(format \"%d-%s\" 5 \"x\")"]
  ["format float"    "\"3.14\""    "(format \"%.2f\" 3.14159)"])
