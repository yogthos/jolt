; Jolt Standard Library: jolt.shell
; Shell command execution via Janet's os/shell.

(defn sh
  [& args]
  (let [cmd (apply str (interpose " " args))
        result (os/shell cmd)]
    {:exit (result 0) :out (result 1) :err (result 2)}))

(defn shell
  [& args]
  (:out (apply sh args)))
