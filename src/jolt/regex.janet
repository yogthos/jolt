# Minimal regex support for Jolt, backed by Janet's PEG engine.
#
# Janet has no regex engine, so we translate a common subset of regex syntax to
# a PEG grammar and compile it. Supported: literals, `.`, character classes
# `[...]` (incl. ranges and `[^...]`), escapes `\d \w \s \D \W \S \b` (literal),
# quantifiers `* + ? {n} {n,m}`, groups `(...)` and non-capturing `(?:...)`,
# alternation `|`, and anchors `^ $`. Exotic constructs (lookaround,
# backreferences, named groups) are NOT supported and may translate loosely.

(defn- chr [s] (get s 0))

(defn regex? [x] (and (table? x) (= :jolt/regex (x :jolt/type))))

# ---- regex source -> PEG (data) ----

(defn- class-peg [body]
  # body is the inside of [...]; supports ranges a-z and negation ^
  (let [neg (and (> (length body) 0) (= (body 0) (chr "^")))
        b (if neg (string/slice body 1) body)
        parts @[]]
    (var i 0)
    (while (< i (length b))
      (let [c (b i)]
        (if (and (< (+ i 2) (length b)) (= (b (+ i 1)) (chr "-")))
          (do (array/push parts ~(range ,(string/from-bytes c (b (+ i 2))))) (+= i 3))
          (do (array/push parts ~(set ,(string/from-bytes c))) (+= i 1)))))
    (let [alt (if (= 1 (length parts)) (parts 0) ~(choice ,;parts))]
      (if neg ~(if-not ,alt 1) alt))))

(defn- esc-peg [c]
  (case c
    (chr "d") '(range "09")
    (chr "D") '(if-not (range "09") 1)
    (chr "w") '(choice (range "az" "AZ" "09") (set "_"))
    (chr "W") '(if-not (choice (range "az" "AZ" "09") (set "_")) 1)
    (chr "s") '(set " \t\n\r\f")
    (chr "S") '(if-not (set " \t\n\r\f") 1)
    (chr "n") '(set "\n")
    (chr "t") '(set "\t")
    (chr "b") "" # word boundary: approximate as nothing
    ~(set ,(string/from-bytes c)))) # escaped literal

(var parse-alt nil)

(defn- parse-atom [s i]
  # returns [peg next-i]
  (let [c (s i)]
    (cond
      (= c (chr "(")) (do
        # group; support (?: ...)
        (var start (+ i 1))
        (when (and (< (+ i 2) (length s)) (= (s (+ i 1)) (chr "?")) (= (s (+ i 2)) (chr ":")))
          (set start (+ i 3)))
        # find matching close paren (no nesting beyond simple)
        (var depth 1) (var j start)
        (while (and (< j (length s)) (> depth 0))
          (cond (= (s j) (chr "(")) (++ depth)
                (= (s j) (chr ")")) (-- depth))
          (when (> depth 0) (++ j)))
        (let [inner (string/slice s start j)]
          [(parse-alt inner) (+ j 1)]))
      (= c (chr "[")) (let [close (string/find "]" s (+ i 1))]
                        [(class-peg (string/slice s (+ i 1) close)) (+ close 1)])
      (= c (chr ".")) ['(if-not (set "\n") 1) (+ i 1)]
      (= c (chr "\\")) [(esc-peg (s (+ i 1))) (+ i 2)]
      (= c (chr "^")) [~(constant nil) (+ i 1)] # anchor: handled loosely
      (= c (chr "$")) ['-1 (+ i 1)]
      [~(set ,(string/from-bytes c)) (+ i 1)])))

(defn- parse-seq [s]
  # one alternative (no top-level |); returns peg
  (def items @[])
  (var i 0)
  (while (< i (length s))
    (let [c (s i)]
      (if (or (= c (chr "*")) (= c (chr "+")) (= c (chr "?")) (= c (chr "{")))
        (error "quantifier without atom") # shouldn't happen; handled below
        (let [[atom ni] (parse-atom s i)]
          (var ii ni)
          (var quantified false)
          (when (< ii (length s))
            (let [q (s ii)]
              (cond
                (= q (chr "*")) (do (array/push items ~(any ,atom)) (set quantified true) (++ ii))
                (= q (chr "+")) (do (array/push items ~(some ,atom)) (set quantified true) (++ ii))
                (= q (chr "?")) (do (array/push items ~(between 0 1 ,atom)) (set quantified true) (++ ii))
                (= q (chr "{")) (let [close (string/find "}" s ii)
                                      spec (string/slice s (+ ii 1) close)
                                      comma (string/find "," spec)]
                                  (if comma
                                    (let [lo (scan-number (string/slice spec 0 comma))
                                          hir (string/slice spec (+ comma 1))
                                          hi (if (= 0 (length hir)) 1000 (scan-number hir))]
                                      (array/push items ~(between ,lo ,hi ,atom)))
                                    (let [n (scan-number spec)]
                                      (array/push items ~(repeat ,n ,atom))))
                                  (set quantified true) (set ii (+ close 1))))))
          (when (not quantified) (array/push items atom))
          (set i ii)))))
  (if (= 1 (length items)) (items 0) ~(sequence ,;items)))

(set parse-alt (fn [s]
  # split on top-level | and build choice
  (def alts @[]) (var depth 0) (var start 0) (var i 0)
  (while (< i (length s))
    (let [c (s i)]
      (cond
        (= c (chr "(")) (++ depth)
        (= c (chr ")")) (-- depth)
        (= c (chr "[")) (let [close (string/find "]" s i)] (set i (or close i)))
        (and (= c (chr "|")) (= depth 0)) (do (array/push alts (string/slice s start i)) (set start (+ i 1)))))
    (++ i))
  (array/push alts (string/slice s start))
  (if (= 1 (length alts))
    (parse-seq (alts 0))
    ~(choice ,;(map parse-seq alts)))))

(defn compile-regex [source]
  (def body (parse-alt source))
  @{:jolt/type :jolt/regex
    :source source
    :peg (peg/compile ~(<- ,body))           # capture a match anywhere
    :anchored (peg/compile ~(sequence (<- ,body) -1))})  # whole-string match

(defn re-pattern [source]
  (if (regex? source) source (compile-regex source)))

# ---- matching ops ----

(defn re-find [re s]
  (def re (re-pattern re))
  (var result nil) (var pos 0)
  (while (and (nil? result) (<= pos (length s)))
    (let [m (peg/match (re :peg) s pos)]
      (if m (set result (m 0)) (++ pos))))
  result)

(defn re-matches [re s]
  (def re (re-pattern re))
  (let [m (peg/match (re :anchored) s)]
    (if m (m 0) nil)))

(defn re-seq [re s]
  (def re (re-pattern re))
  (def out @[]) (var pos 0)
  (while (<= pos (length s))
    (let [m (peg/match (re :peg) s pos)]
      (if m
        (let [matched (m 0)]
          (array/push out matched)
          (set pos (+ pos (max 1 (length matched)))))
        (++ pos))))
  out)

# split string s on matches of regex re; returns array of strings
(defn re-split [re s]
  (def re (re-pattern re))
  (def out @[]) (var pos 0) (var last 0)
  (while (<= pos (length s))
    (let [m (peg/match (re :peg) s pos)]
      (if (and m (> (length (m 0)) 0))
        (do (array/push out (string/slice s last pos))
            (set pos (+ pos (length (m 0))))
            (set last pos))
        (++ pos))))
  (array/push out (string/slice s last))
  out)

# replace all matches of re in s with replacement string
(defn re-replace-all [re s replacement]
  (def re (re-pattern re))
  (def buf @"") (var pos 0) (var last 0)
  (while (<= pos (length s))
    (let [m (peg/match (re :peg) s pos)]
      (if (and m (> (length (m 0)) 0))
        (do (buffer/push-string buf (string/slice s last pos))
            (buffer/push-string buf replacement)
            (set pos (+ pos (length (m 0))))
            (set last pos))
        (++ pos))))
  (buffer/push-string buf (string/slice s last))
  (string buf))
