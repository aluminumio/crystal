# `CrystalGC` is the namespace for garbage-collector *backends*.
#
# The public, user-facing API lives in the `GC` module (see `gc.cr` and the
# `GC` reopenings in each backend file). `GC` is a thin facade: it owns the
# cross-cutting policy (allocation tracing, the read/write lock used to
# coordinate with stop-the-world, the `before_collect` hook, finalizer
# bookkeeping) and delegates every actual memory operation to the backend that
# was selected at compile time.
#
# A backend is an ordinary module exposing the class methods documented below.
# Exactly one backend is compiled into a program, chosen via compile flags:
#
# * `CrystalGC::Boehm` — the default, wrapping the Boehm-Demers-Weiser
#   conservative collector (`libgc`). See `gc/boehm.cr`.
# * `CrystalGC::None` — `libc` `malloc`/`free`, no collection. Selected with
#   `-Dgc_none` or on `wasm32`. See `gc/none.cr`.
#
# This indirection exists so that a precise collector (Immix, behind
# `-Dgc=immix`) can be added later without touching the `GC` facade or any of
# its callers — only a new `CrystalGC::Immix` module and a require switch in
# `gc.cr` are needed.
#
# ## Backend contract
#
# Every backend MUST provide the following class methods. There is no runtime
# polymorphism: conformance is by duck typing and is verified by the backend
# specs (`spec/std/gc/*_spec.cr`).
#
# ### Allocation
#
# * `alloc(size : LibC::SizeT) : Void*` — allocate `size` bytes of cleared
#   memory that may contain managed pointers. The GC scans the result for
#   references.
# * `alloc_atomic(size : LibC::SizeT) : Void*` — allocate `size` bytes that are
#   guaranteed to contain no managed pointers (the GC will not scan it). The
#   memory is not required to be cleared.
# * `realloc(ptr : Void*, size : LibC::SizeT) : Void*` — grow/shrink a previous
#   allocation, preserving its contents up to the smaller of the two sizes.
# * `free(ptr : Void*) : Nil` — explicitly release an allocation. May be a
#   no-op for backends that only reclaim during collection.
#
# ### Collection
#
# * `collect : Nil` — run a full collection cycle.
# * `enable : Nil` / `disable : Nil` — allow / suppress automatic collection.
# * `disabled? : Bool` — whether automatic collection is currently suppressed.
#
# ### Introspection
#
# * `stats : GC::Stats` — coarse heap accounting (see `GC::Stats`).
# * `prof_stats : GC::ProfStats` — detailed profiling counters.
# * `is_heap_ptr?(ptr : Void*) : Bool` — whether `ptr` points into the managed
#   heap.
# * `enumerate_objects(&block : UInt64, Void*, LibC::SizeT ->) : Nil` — yield
#   `{type_id, address, size}` for every live object. Conservative backends
#   that cannot identify object types (e.g. Boehm) raise `NotImplementedError`;
#   a precise backend (Phase 3+) implements this for real and it is the
#   foundation of the heap-introspection tooling (Phase 4).
#
# ### Stack registration
#
# * `register_stack(stack_bottom : Void*, stack_top : Void*) : Nil` — declare a
#   region (e.g. a fiber stack) that the collector must scan for roots.
# * `unregister_stack(stack_bottom : Void*, stack_top : Void*) : Nil` — undo a
#   previous `register_stack`.
#
#   For conservative backends that already discover stacks on their own
#   (Boehm), these are no-ops; a precise backend uses them to track the set of
#   stacks to scan.
module CrystalGC
end
