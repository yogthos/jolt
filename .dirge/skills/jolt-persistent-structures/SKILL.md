---
name: jolt-persistent-structures
description: PersistentHashMap, PersistentHashSet, and LazySeq implementation patterns in Janet tables
---

# jolt-persistent-structures

PersistentHashMap, PersistentHashSet, and LazySeq implementation patterns in Janet tables.

## PersistentHashMap

Bucket-based immutable hash map using copy-on-write. Stores data in `:buckets` (array of flat `[k v k v ...]` bucket arrays), `:cnt` (entry count), `:jolt/deftype` type tag, and `:_meta`.

### Core functions (in phm.janet)
- `make-phm [& kvs]` — create from key-value pairs
- `phm-get [m k &opt default]` — lookup with optional default
- `phm-assoc [m k v]` — return new map with k→v
- `phm-dissoc [m k]` — return new map without k
- `phm-contains? [m k]` — membership check
- `phm-count [m]` — number of entries
- `phm-to-struct [m]` — convert to Janet struct (for equality, keys, vals)
- `phm-entries [m]` — return `[[k v] ...]` pairs

### Core function integration (core.janet)
Each core fn checks `phm?` first, then falls through to struct/table logic:
- `core-get` → `phm-get`
- `core-assoc` → `phm-assoc`  
- `core-dissoc` → `phm-dissoc`
- `core-contains?` → `phm-contains?`
- `core-count` → `phm-count`
- `core-keys/vals/seq` → via `phm-to-struct`
- `core-merge/merge-with` → PHM-aware iteration
- `core-empty?` → check `:cnt = 0`
- `core-conj` → `phm-assoc` for `[k v]` pairs

### Gotchas
- `core-map?`: `(if (and (table? x) (get x :jolt/deftype)) true false)` — `and` returns last truthy
- `core-count`: subtract 1 for deftype tables
- Equality: `phm-to-struct` → `deep=`
- `core-hash-map` wraps `make-phm`, so all literal maps become PHMs

## PersistentHashSet

Backed by a PersistentHashMap with sentinel `true` values.

### Core functions (in phm.janet)
- `make-phs [& xs]` — create from items
- `phs-conj [s & xs]` — add items (idempotent)
- `phs-disj [s & xs]` — remove items
- `phs-contains? [s x]` — membership
- `phs-count [s]` — cardinality
- `phs-seq [s]` — keys as tuple
- `phs-get [s x &opt default]` — returns x if present
- `phs-to-struct [s]` — convert for equality via `deep=`

### Special forms (evaluator.janet)
- `:jolt/set` handler: `(apply make-phs (form :value))`
- `"disj"` dispatch — validates set?, calls `phs-disj`
- `"set?"` dispatch — calls `set?` predicate

## LazySeq

Realize-once thunk wrapper.

### Core functions (in phm.janet)
- `make-lazy-seq [thunk]` — create from thunk
- `realize-ls [ls]` — force + cache (recursive)
- `ls-first/ls-rest/ls-seq/ls-count`

### Gotchas
- Use `indexed?` not `tuple?` for realized sequences
- Avoid `val'` (parse error), use `vf`