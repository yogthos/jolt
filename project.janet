(declare-project
  :name "jolt"
  :description "Clojure interpreter on Janet")

(declare-source
  :source @["src"])

(declare-executable
  :name "jolt"
  :entry "src/jolt/main.janet")
