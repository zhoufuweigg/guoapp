import 'dart:async';

import 'package:flutter/foundation.dart';

import 'core_bridge.dart';
import 'follow_state.dart';
import 'local_store.dart';
import 'models.dart';

const episodeGroupSize = 30;

class DramaDetails extends ChangeNotifier {
  DramaDetails(this.repository, this.store, Drama drama)
    : _drama = repository.catalogUpdates.current(drama),
      _epoch = store.profileEpoch {
    store.addListener(_notify);
    load();
  }
  final AppRepository repository;
  final LocalStore store;
  final int _epoch;
  Drama _drama;
  List<Episode> _episodes = const [];
  String _warning = '';
  String? _error;
  bool _loading = false;
  int _group = 0;
  int _generation = 0;
  bool _disposed = false;

  Drama get drama => _drama;
  List<Episode> get episodes => _episodes;
  String get warning => _warning;
  String? get error => _error;
  bool get loading => _loading;
  bool get allowed =>
      store.profileEpoch == _epoch && store.allowsSource(_drama.source);
  WatchEntry? get watch => allowed ? store.watched(_drama.id) : null;
  int get resumeIndex => resumeEpisodeIndex(_episodes, watch);
  int? get currentIndex {
    final number = watch?.episode;
    final index = _episodes.indexWhere((episode) => episode.number == number);
    return index < 0 ? null : index;
  }

  int get groupCount => (_episodes.length / episodeGroupSize).ceil();
  int get group => _group;
  List<Episode> get groupEpisodes =>
      _episodes.skip(_group * episodeGroupSize).take(episodeGroupSize).toList();

  String groupLabel(int group) {
    final start = group * episodeGroupSize;
    final end = (start + episodeGroupSize).clamp(0, _episodes.length) - 1;
    return '${_episodes[start].number}-${_episodes[end].number}';
  }

  void selectGroup(int group) {
    if (group == _group || group < 0 || group >= groupCount) return;
    _group = group;
    _notify();
  }

  Future<void> load() async {
    if (!allowed) return;
    final generation = ++_generation;
    _loading = true;
    _error = null;
    _notify();
    try {
      final detail = await repository.detail(_drama);
      if (!_current(generation)) return;
      _drama = repository.catalogUpdates.current(_drama).merge(detail.drama);
      _episodes = detail.episodes;
      _warning = detail.warning;
      _group = groupCount == 0 ? 0 : resumeIndex ~/ episodeGroupSize;
      _loading = false;
      _notify();
      repository.catalogUpdates.publish(_drama, retryCover: true);
      unawaited(store.refreshDrama(_drama).catchError((Object _) {}));
      unawaited(_supplement(generation));
    } catch (error) {
      if (!_current(generation)) return;
      _error = error.toString();
      _loading = false;
      _notify();
      repository.catalogUpdates.publish(_drama, retryCover: true);
    }
  }

  Future<void> _supplement(int generation) async {
    try {
      final fresh = await repository.supplementMetadata(_drama);
      if (fresh == null || !_current(generation)) return;
      _drama = _drama.merge(fresh);
      _notify();
      repository.catalogUpdates.publish(_drama);
      await store.refreshDrama(_drama);
    } catch (_) {}
  }

  bool _current(int generation) =>
      !_disposed && generation == _generation && allowed;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    store.removeListener(_notify);
    super.dispose();
  }
}
