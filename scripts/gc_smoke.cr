# Backend-agnostic smoke test for the `CrystalGC` interface (epic #1, Phase 1).
#
# This program must compile *and run* under every GC backend that the compiler
# can target, so it is the harness for testing "Boehm vs. the new GC path" side
# by side:
#
#     crystal run scripts/gc_smoke.cr             # Boehm (default)
#     crystal run -Dgc_none scripts/gc_smoke.cr   # libc malloc, no collection
#     crystal run -Dgc=immix scripts/gc_smoke.cr  # precise Immix GC (Phase 3+)
#
# It exercises the allocation / collection / stats / enable-disable surface of
# the public `GC` facade — which now delegates to a `CrystalGC` backend — so any
# backend wired through the interface is shown to be functional end to end.
# Assertions are kept backend-neutral (e.g. it does not assume a non-zero heap
# size, which `gc_none` reports as 0).

class GCSmokeNode
  property succ : GCSmokeNode?
  @payload : Bytes

  def initialize(@payload : Bytes)
    @succ = nil
  end
end

# Builds a singly-linked chain so the collector has a graph of live references
# to walk (and, once dropped, garbage to reclaim).
def build_chain(count : Int32) : GCSmokeNode?
  head = nil
  count.times do
    node = GCSmokeNode.new(Bytes.new(64))
    node.succ = head
    head = node
  end
  head
end

chain = build_chain(50_000)
raise "allocation produced no chain" if chain.nil?

# Drop the chain and collect; must not crash on any backend.
chain = nil
GC.collect

stats = GC.stats
raise "GC.stats returned #{stats.class}, expected GC::Stats" unless stats.is_a?(GC::Stats)

# A disable -> enable round-trip must be safe on every backend.
GC.disable
GC.enable

# The heap must still be usable after a collection.
again = Array(GCSmokeNode).new(1_000) { GCSmokeNode.new(Bytes.new(8)) }
raise "post-collect allocation failed" unless again.size == 1_000

puts "gc smoke OK"
