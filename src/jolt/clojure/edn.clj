; Jolt Standard Library: clojure.edn
; EDN reading and writing (stubs using the Jolt reader).

(defn read-string
  [s]
  (let [ctx ((get (dyn :current-env) (symbol "init")))]
    ((get (dyn :current-env) (symbol "eval-string")) ctx s)))

(defn read
  [reader]
  (let [line ((get (dyn :current-env) (symbol "file/read")) reader :line)]
    (when line
      (read-string line))))
