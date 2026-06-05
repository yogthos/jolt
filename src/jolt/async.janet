# clojure.core.async on Janet fibers.
#
# Janet fibers are stackful coroutines, so a `go` block is just "run the body in
# a fiber" — the body parks on a channel op by yielding to the event loop, and
# the whole interpreter call stack rides along on the fiber's stack. No CPS/state
# machine transform (unlike Clojure's `go` macro), so <! / >! work anywhere
# (inside try, nested fns, loops, …).
#
# A channel is a pair of Janet ev/chans wrapped in a tagged table: a `:ch` that
# carries values and a `:done` that is closed to signal channel close. A take is
# `(ev/select :ch :done)` — ev/select checks in order, so buffered values drain
# before the close signal is seen, giving Clojure's drain-then-nil semantics. We
# use a separate `:done` channel because Janet's ev/chan-close *discards* a
# channel's buffered values. close! just closes :done (idempotent, no fiber), so
# nothing leaks.
#
# Single OS thread: go blocks run cooperatively on the event loop, so <! (park)
# and <!! (block) are the same here.

(use ./types)
(use ./pv)
(use ./config)

(defn jolt-chan? [x] (and (table? x) (= :jolt/chan (get x :jolt/type))))

(defn- wrap [vc dc] @{:jolt/type :jolt/chan :ch vc :done dc :closed @[false]})

(defn- vchan [x]
  (if (jolt-chan? x) (x :ch) (error (string "expected a channel, got " (type x)))))

(defn- reduced? [x] (and (table? x) (= :jolt/reduced (get x :jolt/type))))

# Buffer specs: (buffer n) fixed, (dropping-buffer n) drops new values when full,
# (sliding-buffer n) drops the oldest when full.
(defn async-buffer [n]          @{:jolt/type :jolt/buffer :kind :fixed :n n})
(defn async-dropping-buffer [n] @{:jolt/type :jolt/buffer :kind :dropping :n n})
(defn async-sliding-buffer [n]  @{:jolt/type :jolt/buffer :kind :sliding :n n})
(defn- buffer-spec? [x] (and (table? x) (= :jolt/buffer (get x :jolt/type))))

# An always-ready channel, used as the non-blocking fallback in ev/select so a
# give can detect "buffer full" without parking.
(def- full-signal (let [c (ev/chan)] (ev/chan-close c) c))

# Put one value into the channel's value chan honoring its buffer kind. Returns
# true (the put "succeeds" even when dropped, like Clojure's dropping/sliding).
(defn- buf-give [ch v]
  (case (ch :bufkind)
    :dropping (do (ev/select [(ch :ch) v] full-signal) true)   # give if room, else drop
    :sliding  (let [r (ev/select [(ch :ch) v] full-signal)]
                (when (= :close (in r 0))                       # full: drop oldest, then add
                  (protect (ev/take (ch :ch))) (protect (ev/give (ch :ch) v)))
                true)
    (if (in (protect (ev/give (ch :ch) v)) 0) true false)))    # fixed/unbuffered: may park

# A channel transducer is applied on the put side. We build a reducing fn whose
# step gives each output value into the channel (honoring its buffer kind); the
# accumulator is the chan, threaded through but unused (output is the
# side-effecting give). A jolt transducer/rf is a jolt closure, directly
# callable as a Janet function.
(defn- make-add-rf [w]
  (fn [& args]
    (case (length args)
      0 (w :ch)                   # init
      1 (in args 0)               # completion: nothing extra to do
      (do (buf-give w (in args 1)) (in args 0)))))   # step: give output

# (chan) unbuffered; (chan n) / (chan (buffer n)) fixed; (chan (dropping-buffer
# n)) / (chan (sliding-buffer n)); a 2nd arg transducer composes over the buffer.
(defn async-chan [&opt buf xform]
  (def spec (cond
              (buffer-spec? buf) buf
              (and (number? buf) (> buf 0)) {:kind :fixed :n buf}
              nil))
  (def vc (if spec (ev/chan (spec :n)) (ev/chan)))
  (def w (wrap vc (ev/chan)))
  (when spec (put w :bufkind (spec :kind)))
  (when (and xform (not (nil? xform)))
    (put w :xrf (xform (make-add-rf w))))
  w)

(defn async-close! [ch]
  (when (not (in (ch :closed) 0))
    (put (ch :closed) 0 true)
    # flush any buffered state of a stateful transducer (completion arity)
    (when (ch :xrf) (protect ((ch :xrf) (ch :ch))))
    (protect (ev/chan-close (ch :done))))
  nil)

# <! / <!! — take, parking the fiber. Drains buffered values, then returns nil
# once the channel is closed and empty.
(defn async-take [ch]
  (def r (ev/select (ch :ch) (ch :done)))
  (if (= :take (in r 0)) (in r 2) nil))

# >! / >!! — put, parking the fiber. Returns true if delivered, false if the
# channel is closed. nil may not be put on a channel (it is the closed value).
# With a transducer, the value is run through it (so one put may yield zero or
# more values on the channel); a `reduced` result (e.g. from `take`) closes it.
(defn async-give [ch v]
  (when (nil? v) (error "Can't put nil on a channel"))
  (cond
    (in (ch :closed) 0) false
    (ch :xrf)
      (let [r ((ch :xrf) (ch :ch) v)]
        (when (reduced? r) (async-close! ch))
        true)
    (buf-give ch v)))

# Run thunk (a jolt 0-arg closure, directly callable) in a fiber; return a
# buffered(1) channel that conveys its value once, then closes. A nil result
# just closes. Buffered(1) so a fire-and-forget go leaves no parked fiber.
#
# The dynamic-var bindings in effect at spawn time are conveyed into the fiber
# (Clojure binding conveyance): we snapshot them here (on the spawning fiber)
# and install a private copy inside the new fiber before running the body.
(defn async-go-spawn [thunk]
  (def snap (snapshot-bindings))
  (def w (async-chan 1))
  (ev/go (fn []
           (install-bindings snap)
           (def res (protect (thunk)))
           (when (and (in res 0) (not (nil? (in res 1))))
             (async-give w (in res 1)))
           (async-close! w)))
  w)

# (alts! [ch ...]) — take from whichever channel is ready first; returns
# [value channel] (value is nil if that channel closed). Take-only for v1.
(defn async-alts [chans]
  (def cs (cond (pvec? chans) (pv->array chans)
                (tuple? chans) chans
                (array? chans) chans
                (error "alts! expects a vector of channels")))
  (def raws @[])
  (def lookup @{})            # raw ev/chan -> [jolt-chan done?]
  (each c cs
    (array/push raws (c :ch))   (put lookup (c :ch)   [c false])
    (array/push raws (c :done)) (put lookup (c :done) [c true]))
  (def r (ev/select ;raws))
  (def info (get lookup (in r 1)))
  (def jc (in info 0))
  (def val (if (or (in info 1) (not= :take (in r 0))) nil (in r 2)))
  (pv-from-indexed @[val jc]))

# (timeout ms) — a channel that closes after ms milliseconds.
(defn async-timeout [ms]
  (def w (async-chan))
  (ev/go (fn [] (ev/sleep (/ ms 1000)) (async-close! w)))
  w)

# (put! ch v [cb]) — async put; (take! ch cb) — async take. Fire a fiber and
# call the optional callback with the result.
(defn async-put! [ch v &opt cb]
  (ev/go (fn []
           (def ok (async-give ch v))
           (when (and cb (not (nil? cb))) (cb ok))))
  nil)
(defn async-take! [ch cb]
  (ev/go (fn []
           (def val (async-take ch))
           (when (and cb (not (nil? cb))) (cb val))))
  nil)

# --- macros (Janet macro-fns that return forms) ---

(defn- sym [name &opt ns] {:jolt/type :symbol :ns ns :name name})

# (go body...) -> (go-spawn (fn* [] body...))
(defn async-go [& body]
  @[(sym "go-spawn" "clojure.core.async") (array (sym "fn*") [] ;body)])

# (go-loop bindings body...) -> (go (loop bindings body...))
(defn async-go-loop [bindings & body]
  @[(sym "go" "clojure.core.async") (array (sym "loop") bindings ;body)])

# (thread body...) — runs cooperatively in a fiber here (no OS thread); same
# shape as go (returns a result channel).
(defn async-thread [& body]
  @[(sym "go-spawn" "clojure.core.async") (array (sym "fn*") [] ;body)])

(def- async-bindings
  @{"chan" async-chan
    "chan?" jolt-chan?
    "close!" async-close!
    "<!" async-take   "<!!" async-take
    ">!" async-give   ">!!" async-give
    "alts!" async-alts "alts!!" async-alts
    "timeout" async-timeout
    "buffer" async-buffer
    "dropping-buffer" async-dropping-buffer
    "sliding-buffer" async-sliding-buffer
    "put!" async-put!
    "take!" async-take!
    "go-spawn" async-go-spawn
    "go" async-go
    "go-loop" async-go-loop
    "thread" async-thread})

(def- async-macros @{"go" true "go-loop" true "thread" true})

(defn install-async!
  "Create/populate the clojure.core.async namespace in ctx."
  [ctx]
  (let [ns (ctx-find-ns ctx "clojure.core.async")]
    (loop [[name f] :pairs async-bindings]
      (def v (ns-intern ns name f))
      (when (get async-macros name) (put v :macro true)))
    ns))
