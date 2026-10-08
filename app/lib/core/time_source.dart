import 'package:clock/clock.dart';

/// Audit timestamps and elapsed time have separate authorities. Clock changes
/// must never change a retry delay or accumulated actual execution time.
abstract interface class TimeSource {
  DateTime get utcNow;
  Duration get monotonic;
}

final class SystemTimeSource implements TimeSource {
  final Stopwatch _stopwatch = Stopwatch()..start();
  @override
  DateTime get utcNow => clock.now().toUtc();
  @override
  Duration get monotonic => _stopwatch.elapsed;
}
