(use ./src/jolt/reader)

(def src (slurp "/Users/yogthos/src/sci/src/sci/impl/utils.cljc"))
(var s src)
(for i 1 14
  (let [p (parse-next s)]
    (set s (in p 1))))

(def [form15 rest] (parse-next s))
(if (array? form15)
  (printf "form15: (%s ...)" (get (first form15) :name))
  (printf "form15: %q" form15))
(printf " => OK, rest: %d bytes" (length rest))
