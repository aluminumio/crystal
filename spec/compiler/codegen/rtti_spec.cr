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
