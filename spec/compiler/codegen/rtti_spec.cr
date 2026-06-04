require "../../spec_helper"

# Phase 2 (epic #1): the compiler emits a Runtime Type Information table indexed
# by `crystal_type_id` when built with `-Drtti`. These specs compile and run real
# programs that read the table back through `Crystal::RTTI`, cross-checking the
# emitted reference-field offsets against `offsetof` so they agree with the real
# object layout — the property a precise GC depends on.
describe "Code gen: RTTI type descriptors" do
  it "records reference-field offsets (the precise-GC scan list)" do
    run(<<-CRYSTAL, flags: ["rtti"]).to_b.should be_true
      require "prelude"

      class RTTIRef
      end

      class RTTIFoo
        @a : Int32 = 1
        @b : String = "x"
        @c : Int64 = 2
        @d : RTTIRef = RTTIRef.new
      end

      desc = Crystal::RTTI.descriptor(RTTIFoo.new)
      expected = [offsetof(RTTIFoo, @b).to_u32, offsetof(RTTIFoo, @d).to_u32].sort!
      got = desc.reference_offsets.to_a.sort!
      got == expected
      CRYSTAL
  end

  it "reports name and instance_size" do
    run(<<-CRYSTAL, flags: ["rtti"]).to_b.should be_true
      require "prelude"

      class RTTIBar
        @x : Int32 = 0
      end

      d = Crystal::RTTI.descriptor(RTTIBar.new)
      d.name == "RTTIBar" && d.instance_size == instance_sizeof(RTTIBar)
      CRYSTAL
  end

  it "marks a pointer-free class atomic with no reference offsets" do
    run(<<-CRYSTAL, flags: ["rtti"]).to_b.should be_true
      require "prelude"

      class RTTIAtomic
        @x : Int32 = 0
        @y : Float64 = 0.0
      end

      d = Crystal::RTTI.descriptor(RTTIAtomic.new)
      d.atomic? && d.reference_offsets.empty?
      CRYSTAL
  end

  it "indexes by the object's crystal_type_id" do
    run(<<-CRYSTAL, flags: ["rtti"]).to_b.should be_true
      require "prelude"

      class RTTIById
        @ref : String = "y"
      end

      obj = RTTIById.new
      by_obj = Crystal::RTTI.descriptor(obj)
      by_id = Crystal::RTTI.descriptor(obj.crystal_type_id)
      by_obj.type_id == obj.crystal_type_id && by_id.name == "RTTIById"
      CRYSTAL
  end

  # The real test of "is the RTTI helpful?": can you use it to precisely walk an
  # object's outgoing managed pointers — the exact operation a precise GC mark
  # phase performs? These read live object memory through the descriptor.
  it "Crystal::RTTI.each_outgoing_reference enumerates an object's live heap pointers" do
    run(<<-CRYSTAL, flags: ["rtti"]).to_b.should be_true
      require "prelude"

      class WNode
        property nxt : WNode?
        property name : String

        def initialize(@name, @nxt = nil)
        end
      end

      leaf = WNode.new("leaf")
      root = WNode.new("root", leaf)

      seen = [] of UInt64
      Crystal::RTTI.each_outgoing_reference(root) { |p| seen << p.address }
      # root's live references are @name (a String) and @nxt (leaf); a nil @nxt
      # would be skipped. Order-independent.
      seen.includes?(leaf.as(Void*).address) &&
        seen.includes?(root.name.as(Void*).address) &&
        seen.size == 2
      CRYSTAL
  end

  it "flattens embedded value-struct pointers to exact offsets (precise, not the struct start)" do
    run(<<-CRYSTAL, flags: ["rtti"]).to_b.should be_true
      require "prelude"

      struct WInner
        @pad : Int32 = 7
        @s : String

        def initialize(@s)
        end
      end

      class WOuter
        @flag : Int32 = 1
        @inner : WInner

        def initialize(@inner)
        end
      end

      s = "embedded-string"
      o = WOuter.new(WInner.new(s))

      seen = [] of UInt64
      Crystal::RTTI.each_outgoing_reference(o) { |p| seen << p.address }
      # The String lives inside the embedded WInner value struct; precise RTTI
      # must point at it directly, so the walker finds it.
      seen.includes?(s.as(Void*).address)
      CRYSTAL
  end

  it "scans Array buffer elements for references (variable-length container)" do
    run(<<-CRYSTAL, flags: ["rtti"]).to_b.should be_true
      require "prelude"

      a = ["alpha", "beta", "gamma"]
      seen = [] of UInt64
      Crystal::RTTI.each_outgoing_reference(a) { |p| seen << p.address }
      # Precise marking of the Array must reach every element String stored in
      # its separately-allocated buffer.
      a.all? { |s| seen.includes?(s.as(Void*).address) }
      CRYSTAL
  end

  it "reports an Array's element layout (buffer/size offsets, element type)" do
    run(<<-CRYSTAL, flags: ["rtti"]).to_b.should be_true
      require "prelude"

      d = Crystal::RTTI.descriptor([1, 2, 3])
      d.container? &&
        d.buffer_offset == offsetof(Array(Int32), @buffer) &&
        d.size_offset == offsetof(Array(Int32), @size)
      CRYSTAL
  end

  it "gives distinct generic instantiations their own descriptors" do
    run(<<-CRYSTAL, flags: ["rtti"]).to_b.should be_true
      require "prelude"

      class RTTIBox(T)
        @value : T

        def initialize(@value : T)
        end
      end

      di = Crystal::RTTI.descriptor(RTTIBox(Int32).new(1))
      ds = Crystal::RTTI.descriptor(RTTIBox(String).new("z"))
      # Int32 payload: no managed pointer; String payload: one reference offset.
      di.type_id != ds.type_id && di.reference_offsets.empty? && ds.reference_offsets.size == 1
      CRYSTAL
  end
end
