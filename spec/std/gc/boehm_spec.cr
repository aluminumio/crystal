require "../spec_helper"

# Phase 1: GC backend interface abstraction (crystal-lang/crystal exploration #2).
#
# These specs pin the contract that the `CrystalGC::Boehm` backend must satisfy
# as the data-plane behind the public `GC` facade. They are guarded to the
# configurations where the Boehm backend is actually compiled in.
{% unless flag?(:gc_none) || flag?(:wasm32) %}
  describe CrystalGC::Boehm do
    it "alloc returns a non-null, heap-tracked pointer" do
      ptr = CrystalGC::Boehm.alloc(LibC::SizeT.new(64))
      ptr.null?.should be_false
      CrystalGC::Boehm.is_heap_ptr?(ptr).should be_true
    end

    it "alloc_atomic returns a non-null pointer" do
      ptr = CrystalGC::Boehm.alloc_atomic(LibC::SizeT.new(64))
      ptr.null?.should be_false
    end

    it "realloc preserves existing data" do
      ptr = CrystalGC::Boehm.alloc(LibC::SizeT.new(8)).as(UInt8*)
      ptr.value = 42_u8
      bigger = CrystalGC::Boehm.realloc(ptr.as(Void*), LibC::SizeT.new(4096)).as(UInt8*)
      bigger.value.should eq(42_u8)
    end

    it "collect runs without error" do
      CrystalGC::Boehm.collect
    end

    it "stats returns a populated GC::Stats" do
      stats = CrystalGC::Boehm.stats
      stats.should be_a(GC::Stats)
      stats.heap_size.should be > 0
    end

    it "prof_stats returns a GC::ProfStats" do
      CrystalGC::Boehm.prof_stats.should be_a(GC::ProfStats)
    end

    it "disable / enable round-trip is observable via disabled?" do
      CrystalGC::Boehm.disabled?.should be_false
      CrystalGC::Boehm.disable
      CrystalGC::Boehm.disabled?.should be_true
    ensure
      CrystalGC::Boehm.enable
      CrystalGC::Boehm.disabled?.should be_false
    end

    it "register_stack / unregister_stack accept a region" do
      # Boehm scans stacks via its own machinery, so these are no-ops; the
      # contract is only that they exist and accept a [bottom, top) region.
      buffer = uninitialized UInt8[256]
      bottom = pointerof(buffer).as(Void*)
      top = (pointerof(buffer).as(UInt8*) + 256).as(Void*)
      CrystalGC::Boehm.register_stack(bottom, top)
      CrystalGC::Boehm.unregister_stack(bottom, top)
    end

    it "enumerate_objects raises NotImplementedError (Boehm is conservative)" do
      expect_raises(NotImplementedError) do
        CrystalGC::Boehm.enumerate_objects { |_type_id, _address, _size| }
      end
    end
  end
{% end %}
