# Specification: destructuring (in let, fn, loop, doseq, for).
(use ../support/harness)

(defspec "destructure / sequential"
  ["basic vector"       "3"      "(let [[a b] [1 2]] (+ a b))"]
  ["skip with _"        "3"      "(let [[_ b] [1 2]] (+ b 1))"]
  ["rest with &"        "[3 4]"  "(let [[a & more] [1 3 4]] more)"]
  [":as whole"          "[1 2]"  "(let [[a :as v] [1 2]] v)"]
  ["nested"             "3"      "(let [[[a b]] [[1 2]]] (+ a b))"]
  ["fewer values nil"   "nil"    "(let [[a b c] [1 2]] c)"]
  ["over a list"        "1"      "(let [[a] (list 1 2)] a)"]
  ["over a seq"         "2"      "(let [[a b] (rest [9 1 2])] b)"]
  ["string chars"       "\\a"    "(let [[a] (seq \"ab\")] a)"])

(defspec "destructure / associative"
  ["keys"               "3"      "(let [{:keys [a b]} {:a 1 :b 2}] (+ a b))"]
  [":as map"            "{:a 1}" "(let [{:as m} {:a 1}] m)"]
  [":or default"        "9"      "(let [{:keys [a] :or {a 9}} {}] a)"]
  [":or present"        "1"      "(let [{:keys [a] :or {a 9}} {:a 1}] a)"]
  ["explicit binding"   "1"      "(let [{x :a} {:a 1}] x)"]
  ["nested map"         "2"      "(let [{{b :b} :a} {:a {:b 2}}] b)"]
  ["keys + as"          "[1 {:a 1}]" "(let [{:keys [a] :as m} {:a 1}] [a m])"]
  ["map in vector"      "1"      "(let [[{:keys [a]}] [{:a 1}]] a)"])

(defspec "destructure / in forms"
  ["fn params"          "3"      "((fn [[a b]] (+ a b)) [1 2])"]
  ["fn map param"       "1"      "((fn [{:keys [a]}] a) {:a 1})"]
  ["defn destructure"   "3"      "(do (defn f [[a b]] (+ a b)) (f [1 2]))"]
  ["loop destructure"   "3"      "(loop [[a b] [1 2]] (+ a b))"]
  ["doseq destructure"  "12"     "(let [s (atom 0)] (doseq [[k v] {:a 4 :b 8}] (swap! s (fn [x] (+ x v)))) @s)"]
  ["for destructure"    "[3 7]"  "(for [[a b] [[1 2] [3 4]]] (+ a b))"]
  ["& rest in fn"       "[2 3]"  "((fn [a & more] more) 1 2 3)"])
