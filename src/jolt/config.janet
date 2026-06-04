# Build-time collection mode.
#
# Jolt can be built with either immutable (persistent) collections — proper
# Clojure value semantics — or fast Janet-native mutable collections.
#
#   jpm build                 # immutable (default)
#   JOLT_MUTABLE=1 jpm build  # mutable
#
# This reads the environment at module-load time, so for a jpm-compiled
# executable the value is fixed when the binary is built (a true compile flag).
# `mutable?` is a constant, so the type-mode branches throughout core fold away.
(def mutable? (= "1" (os/getenv "JOLT_MUTABLE")))

# Convenience: immutable? is the default.
(def immutable? (not mutable?))
