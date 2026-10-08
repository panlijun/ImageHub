/// Local system memory pressure only; this interface performs no resource probe.
abstract interface class MemoryPressureMonitor {
  Stream<void> get events;
  Future<void> start();
  Future<void> close();
}
