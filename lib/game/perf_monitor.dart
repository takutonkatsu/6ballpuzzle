import 'dart:developer' as developer;

class PerfMonitor {
  PerfMonitor._();

  static const bool enabled = bool.fromEnvironment('PERF_LOGS');

  static void logDuration(
    String label,
    Stopwatch stopwatch, {
    int warnMs = 8,
  }) {
    if (!enabled) {
      return;
    }
    final elapsedMs = stopwatch.elapsedMicroseconds / 1000.0;
    if (elapsedMs < warnMs) {
      return;
    }
    developer.log(
      '${elapsedMs.toStringAsFixed(2)}ms',
      name: 'perf.$label',
    );
  }

  static void logValue(String label, Object value) {
    if (!enabled) {
      return;
    }
    developer.log('$value', name: 'perf.$label');
  }
}
