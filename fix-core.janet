(def lines (string/split "\n" (slurp "src/jolt/core.janet")))
(def new-lines @[])
(each l lines 
  (array/push new-lines l)
  (if (= l "    new-val))")
    (do
      (array/push new-lines "")
      (array/push new-lines "# Hierarchy (minimal stubs for sci bootstrap)")
      (array/push new-lines "(defn core-derive [tag parent] nil)")
      (array/push new-lines "(defn core-isa? ([child parent] false) ([h child parent] false))")
      (array/push new-lines "(defn core-ancestors ([tag] #{}) ([h tag] #{}))")
      (array/push new-lines "(defn core-descendants ([tag] #{}) ([h tag] #{}))"))))
(spit "src/jolt/core.janet" (string/join new-lines "\n"))
(print "done")
