import 'dart:async';
import 'dart:math';

import 'core_bridge.dart';
import 'follow_state.dart';
import 'local_store.dart';
import 'models.dart';

class FollowUpdater {
  FollowUpdater(
    this.repository,
    this.store, {
    this.startDelay = const Duration(seconds: 30),
    this.interval = const Duration(minutes: 30),
    this.recheck = const Duration(hours: 6),
    this.limit = 10,
    DateTime Function()? clock,
  }) : _epoch = store.profileEpoch,
       _clock = clock ?? DateTime.now;

  static const _maxBackoffShift = 3;

  final AppRepository repository;
  final LocalStore store;
  final Duration startDelay;
  final Duration interval;
  final Duration recheck;
  final int limit;
  final DateTime Function() _clock;
  final int _epoch;
  Timer? _timer;
  bool _running = false;
  bool _disposed = false;

  bool get _valid =>
      !_disposed && !store.locked && _epoch == store.profileEpoch;

  void start() {
    if (_timer != null || !repository.supportsSourceManagement || !_valid) {
      return;
    }
    _timer = Timer(startDelay, () {
      _timer = Timer.periodic(interval, (_) => _tick());
      _tick();
    });
  }

  void _tick() => unawaited(run().catchError((Object _) {}));

  List<Drama> _due(Map<String, FollowCheck> checks) {
    final now = _clock();
    final never = DateTime.fromMillisecondsSinceEpoch(0);
    final items = store.favorites.where((drama) {
      if (const {'finished', 'completed'}.contains(drama.releaseStatus)) {
        return false;
      }
      final check = checks[drama.id];
      return check == null ||
          !now.isBefore(
            check.checkedAt.add(
              recheck * (1 << min(check.failures, _maxBackoffShift)),
            ),
          );
    }).toList();
    items.sort(
      (a, b) => (checks[a.id]?.checkedAt ?? never).compareTo(
        checks[b.id]?.checkedAt ?? never,
      ),
    );
    return items.take(limit).toList();
  }

  Future<void> run() async {
    if (_running || !_valid) return;
    _running = true;
    try {
      final checks = store.followChecks;
      final updates = <Drama>[];
      for (final drama in _due(checks)) {
        if (!_valid) return;
        try {
          updates.add(await repository.followCheck(drama));
          checks[drama.id] = FollowCheck(_clock());
        } catch (_) {
          checks[drama.id] = FollowCheck(
            _clock(),
            failures: (checks[drama.id]?.failures ?? 0) + 1,
          );
        }
      }
      if (!_valid) return;
      if (updates.isNotEmpty) await store.refreshDramas(updates);
      await store.saveFollowChecks(checks, epoch: _epoch);
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
