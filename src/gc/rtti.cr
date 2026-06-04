{% skip_file unless flag?(:rtti) %}

# Runtime Type Information (epic #1, Phase 2).
#
# When a program is built with `-Drtti`, the compiler emits an immutable,
# statically-allocated table of `TypeDescriptor`s indexed by the existing
# `crystal_type_id` (the `Int32` already stored at offset 0 of every reference
# object). The object header is left **byte-for-byte unchanged**; the type id is
# the join key into this side table.
#
# This is the foundation for a precise garbage collector (Phase 3) — the
# `reference_offsets` array is exactly the "GC-able field" offset list a precise
# mark phase walks — and for heap-introspection tooling (Phase 4). The default
# (Boehm) backend never consults it, so it is dead-strippable when unused.
#
# The on-disk layout below MUST match the compiler emission in
# `Crystal::CodeGenVisitor#emit_rtti_table` (`codegen.cr`).
module Crystal::RTTI
  @[Flags]
  enum TypeFlags : UInt32
    Reference # heap-allocated (non-struct): carries the type-id header at offset 0
    Atomic    # contains no managed pointers (allocated via malloc_atomic)
    Extern    # C struct/union: scan conservatively, ignore the precise offset list
    Virtual   # type id is the root of a {min, max} subtype range
  end

  # Per-type descriptor. Field order and types mirror the LLVM struct
  # `{ i32, i32, ptr, ptr, i32, i32 }` emitted by the compiler.
  struct TypeDescriptor
    @type_id : Int32
    @instance_size : UInt32
    @name : String
    @ref_offsets : UInt32*
    @ref_count : UInt32
    @flags : TypeFlags

    # Descriptors are materialized by reinterpreting the compiler-emitted table
    # (`Pointer#value`), not constructed; this initializer only satisfies the
    # nil-analysis and is unused at runtime.
    def initialize(@type_id, @instance_size, @name, @ref_offsets, @ref_count, @flags)
    end

    # The `crystal_type_id` this descriptor describes.
    def type_id : Int32
      @type_id
    end

    # Size in bytes of an instance (including the type-id header).
    def instance_size : UInt32
      @instance_size
    end

    # Fully-qualified type name.
    def name : String
      @name
    end

    # Byte offsets, within an instance, of the fields that contain managed
    # pointers — the precise GC's scan list.
    def reference_offsets : Slice(UInt32)
      Slice.new(@ref_offsets, @ref_count.to_i32, read_only: true)
    end

    # Whether instances contain no managed pointers (allocated atomically).
    def atomic? : Bool
      @flags.atomic?
    end

    # Whether this is a C-interop type that must be scanned conservatively.
    def extern? : Bool
      @flags.extern?
    end
  end

  # Compiler-emitted accessors (defined in the main module, linked here by name
  # — the same `fun __crystal_*` mechanism as `__crystal_main`).
  lib LibRTTI
    fun base = __crystal_type_descriptors_base : Void*
    fun count = __crystal_type_descriptors_count : Int32
  end

  # Number of descriptors in the table (one per `crystal_type_id`).
  def self.count : Int32
    LibRTTI.count
  end

  # The descriptor for a given `crystal_type_id`.
  def self.descriptor(type_id : Int32) : TypeDescriptor
    n = LibRTTI.count
    unless 0 <= type_id < n
      raise IndexError.new("RTTI type_id #{type_id} out of range (0...#{n})")
    end
    (LibRTTI.base.as(TypeDescriptor*) + type_id).value
  end

  # The descriptor for a live heap object, via its type-id header.
  def self.descriptor(obj : Reference) : TypeDescriptor
    descriptor(obj.crystal_type_id)
  end
end
