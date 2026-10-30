import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_profiles.dart';
import 'local_snapshot.dart';
import 'models.dart';
import 'playback_preferences.dart';
import 'download_preferences.dart';
import 'catalog_sort.dart';
import 'follow_state.dart';
import 'hongguo_series.dart';
import 'theme_color.dart';

class LocalStore extends ChangeNotifier {
  LocalStore(
    this.preferences, {
    Future<String> Function(String, String)? pinHasher,
  }) : _pinHasher = pinHasher ?? hashProfilePin {
    _initialize();
  }

  final SharedPreferences preferences;
  final Future<String> Function(String pin, String salt) _pinHasher;
  LocalSnapshot? _snapshot;
  final Map<String, WatchEntry> _history = {};
  final Map<String, Drama> _favorites = {};
  final Map<String, FollowState> _followStates = {};
  final Map<String, Drama> _seriesCandidates = {};
  Future<void> _writes = Future<void>.value();
  List<LocalProfile> _profiles = [];
  String _current = 'default';
  bool _locked = false;
  bool _disposed = false;
  String? _configurationError;
  int _epoch = 0;
  int _failures = 0;
  Map<String, bool> _sourceSwitches = {};
  DateTime _retryAfter = DateTime(2000);

  void _initialize() {
    try {
      _snapshot = LocalSnapshot(preferences);
      final raw = _snapshot!.getString('profiles');
      if (raw == null &&
          (_snapshot!.getString('activeProfile') != null ||
              _snapshot!.values.keys.any(
                (key) => key.startsWith('profile.'),
              ))) {
        throw const FormatException('已有用户配置缺失');
      }
      _profiles = raw == null
          ? [const LocalProfile(id: 'default', name: '管理员', admin: true)]
          : _readProfiles(jsonDecode(raw));
      _current = _snapshot!.getString('activeProfile') ?? 'default';
      if (!_profiles.any((profile) => profile.id == _current)) {
        _current = _profiles.firstWhere((profile) => profile.admin).id;
      }
      _configurationError = null;
      _locked = forceLogin && profile.protected;
      _loadSourceSwitches();
      _loadLibrary();
      _loadSeriesCandidates();
      _queue(() => _moveSeriesCandidates().catchError((Object _) {}));
    } catch (_) {
      _block('本地用户配置损坏，已锁定访问。原始记录已保留，请重新读取或从备份恢复。');
    }
  }

  static List<LocalProfile> _readProfiles(dynamic records) {
    final profiles = (records as List)
        .map(
          (row) => LocalProfile.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
    if (profiles.isEmpty ||
        profiles.length > 20 ||
        profiles.map((profile) => profile.id).toSet().length !=
            profiles.length ||
        profiles.where((profile) => profile.admin).length != 1 ||
        (profiles.length > 1 &&
            !profiles.firstWhere((profile) => profile.admin).protected)) {
      throw const FormatException('用户配置无效');
    }
    return profiles;
  }

  void _block(String message) {
    _configurationError = message;
    _locked = true;
    _profiles = [
      const LocalProfile(id: 'default', name: '配置待恢复', download: false),
    ];
    _current = 'default';
    _history.clear();
    _favorites.clear();
    _followStates.clear();
    _seriesCandidates.clear();
    _epoch++;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String? _string(String key) => _snapshot?.getString(key);
  bool? _bool(String key) => _snapshot?.getBool(key);
  String _key(String key, [String? id]) =>
      (id ?? _current) == 'default' ? key : 'profile.${id ?? _current}.$key';
  String? get configurationError => _configurationError;
  List<LocalProfile> get profiles => List.unmodifiable(_profiles);
  LocalProfile get profile =>
      _profiles.firstWhere((profile) => profile.id == _current);
  bool get locked => _locked || _configurationError != null;
  int get profileEpoch => _epoch;
  bool get forceLogin {
    if (_configurationError != null) return true;
    final admin = _profiles.firstWhere((profile) => profile.admin);
    return _bool('forceLogin') ?? admin.protected;
  }

  bool get canDownload => !locked && (profile.admin || profile.download);
  bool allowsSource(String source) =>
      !locked &&
      SourceSite.isAvailable(source) &&
      profile.allows(source) &&
      sourceEnabled(source);
  List<SourceSite> get sources =>
      SourceSite.values.where((site) => allowsSource(site.id)).toList();
  List<SourceSite> get permittedSources => [
    for (final site in SourceSite.values)
      if (!locked && profile.allows(site.id)) site,
  ];

  bool sourceEnabled(String source) =>
      _sourceSwitches[source] ?? !SourceSite.isRestricted(source);

  void _loadSourceSwitches() {
    try {
      final raw = _string('sourceSwitches');
      _sourceSwitches = raw == null
          ? {}
          : Map<String, bool>.from(jsonDecode(raw) as Map);
    } catch (_) {
      _sourceSwitches = {};
    }
  }

  Future<void> setSourceEnabled(String source, bool enabled) {
    if (!SourceSite.isAvailable(source)) {
      return Future.error(StateError('站源无效'));
    }
    final epoch = _epoch;
    return _queue(() async {
      _requireAdmin();
      if (epoch != _epoch) throw StateError('当前用户已变更，请重试');
      final switches = {..._sourceSwitches, source: enabled};
      await _commit({'sourceSwitches': jsonEncode(switches)});
      _sourceSwitches = switches;
      _notify();
    });
  }

  void _loadLibrary() {
    _history.clear();
    _favorites.clear();
    _followStates.clear();
    if (_configurationError != null) return;
    for (final row in readJsonList(_string(_key('history')))) {
      try {
        final entry = WatchEntry.fromJson(row);
        _history[entry.drama.id] = entry;
      } catch (_) {}
    }
    for (final row in readJsonList(_string(_key('favorites')))) {
      try {
        final drama = Drama.fromJson(row);
        _favorites[drama.id] = drama;
      } catch (_) {}
    }
    Map<String, dynamic> states = {};
    try {
      states = Map<String, dynamic>.from(
        jsonDecode(_string(_key('followStates')) ?? '{}') as Map,
      );
    } catch (_) {}
    for (final drama in _favorites.values) {
      try {
        _followStates[drama.id] = FollowState.fromJson(
          Map<String, dynamic>.from(states[drama.id] as Map),
        );
      } catch (_) {
        _followStates[drama.id] = FollowState.initial(drama);
      }
    }
  }

  String _seriesKey([String? id]) => 'seriesCandidates.${id ?? _current}';
  String _followChecksKey([String? id]) => 'followChecks.${id ?? _current}';

  Map<String, FollowCheck> get followChecks {
    try {
      final data =
          jsonDecode(preferences.getString(_followChecksKey()) ?? '{}') as Map;
      return {
        for (final entry in data.entries)
          entry.key as String: FollowCheck.fromJson(entry.value),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> saveFollowChecks(
    Map<String, FollowCheck> checks, {
    required int epoch,
  }) => _queue(() async {
    if (locked || epoch != _epoch) return;
    await preferences.setString(
      _followChecksKey(),
      jsonEncode({
        for (final entry in checks.entries)
          if (_favorites.containsKey(entry.key))
            entry.key: entry.value.toJson(),
      }),
    );
  });

  void _loadSeriesCandidates() {
    _seriesCandidates.clear();
    if (_configurationError != null) return;
    for (final row in readJsonList(
      preferences.getString(_seriesKey()) ?? _string(_key('seriesCandidates')),
    )) {
      try {
        final drama = Drama.fromJson(row);
        if (drama.source == SourceSite.hongguo.id) {
          _seriesCandidates[drama.id] = drama;
        }
      } catch (_) {}
    }
  }

  Future<void> _moveSeriesCandidates() async {
    if (_configurationError != null) return;
    final legacy = {
      for (final profile in _profiles)
        profile.id: ?_string(_key('seriesCandidates', profile.id)),
    };
    if (legacy.isEmpty) return;
    for (final entry in legacy.entries) {
      if (preferences.getString(_seriesKey(entry.key)) == null) {
        await preferences.setString(_seriesKey(entry.key), entry.value);
      }
    }
    await _commit(
      {},
      remove: legacy.keys.map((id) => _key('seriesCandidates', id)),
    );
  }

  List<WatchEntry> get history =>
      _history.values
          .where((entry) => allowsSource(entry.drama.source))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  List<Drama> get favorites => _favorites.values
      .where((drama) => allowsSource(drama.source))
      .toList()
      .reversed
      .toList();
  WatchEntry? watched(String id) {
    final entry = _history[id];
    return entry != null && allowsSource(entry.drama.source) ? entry : null;
  }

  bool isFavorite(String id) =>
      _favorites[id] != null && allowsSource(_favorites[id]!.source);
  FollowState? following(String id) =>
      isFavorite(id) ? _followStates[id] : null;
  List<Drama> seriesDramasFor(Drama anchor) {
    if (!allowsSource(SourceSite.hongguo.id) ||
        anchor.source != SourceSite.hongguo.id) {
      return const [];
    }
    final items = <String, Drama>{};
    for (final drama in _seriesCandidates.values) {
      if (allowsSource(drama.source)) items[drama.id] = drama;
    }
    for (final drama in _favorites.values) {
      if (allowsSource(drama.source)) items[drama.id] = drama;
    }
    for (final entry in _history.values) {
      if (allowsSource(entry.drama.source)) items[entry.drama.id] = entry.drama;
    }
    final notices = <SeriesSeasonNotice>[
      ...?_followStates[anchor.id]?.seriesSeasons.values,
      for (final state in _followStates.values)
        if (state.seriesSeasons.containsKey(anchor.id))
          state.seriesSeasons[anchor.id]!,
    ];
    for (final notice in notices) {
      items.putIfAbsent(
        notice.id,
        () => Drama(
          id: notice.id,
          source: SourceSite.hongguo.id,
          sourceId: notice.id.substring(SourceSite.hongguo.id.length + 1),
          title: notice.title,
        ),
      );
    }
    final current = items.remove(anchor.id) ?? anchor;
    final rest = items.values.toList()
      ..sort((a, b) => naturalTitleCompare(a.title, b.title));
    return [current, ...rest];
  }

  bool get hideVip =>
      _configurationError == null ? _bool(_key('hideVip')) ?? true : true;
  String get displayMode {
    final value = _configurationError == null ? _string('displayMode') : null;
    return {'auto', 'television', 'phone', 'pad', 'window'}.contains(value)
        ? value!
        : 'auto';
  }

  String get themeMode {
    final value = _configurationError == null ? _string('themeMode') : null;
    return {'light', 'dark', 'system'}.contains(value) ? value! : 'system';
  }

  bool get followSystemColor =>
      preferences.getBool('followSystemColor') ?? true;
  ThemeColor get themeColor =>
      ThemeColor.byName(preferences.getString('themeColor')) ??
      ThemeColor.orange;
  bool get sideBarExpanded => preferences.getBool('sideBarExpanded') ?? true;
  bool get playerWide => preferences.getBool('playerWide') ?? false;
  ({double left, double top, double extent})? get miniWindow {
    final values = preferences
        .getString('miniWindow')
        ?.split(',')
        .map(double.tryParse)
        .toList();
    if (values == null || values.length != 3 || values.contains(null)) {
      return null;
    }
    return (left: values[0]!, top: values[1]!, extent: values[2]!);
  }

  bool get televisionKeyboard =>
      preferences.getBool('televisionKeyboard') ?? false;
  bool get checkUpdates => preferences.getBool('checkUpdates') ?? true;
  bool get autoExport => preferences.getBool('autoExport') ?? false;
  bool get deleteAfterAutoExport =>
      preferences.getBool('deleteAfterAutoExport') ?? false;
  bool get deleteAfterManualExport =>
      preferences.getBool('deleteAfterManualExport') ?? false;
  bool get shareUsage => preferences.getBool('shareUsage') ?? true;
  String get ignoredUpdate => preferences.getString('ignoredUpdate') ?? '';

  String get source {
    if (locked) return '';
    final value = _string(_key('source')) ?? '';
    return sources.any((site) => site.id == value)
        ? value
        : sources.firstOrNull?.id ?? '';
  }

  DownloadPreferences get downloadPreferences {
    if (locked) return const DownloadPreferences();
    try {
      return DownloadPreferences.fromJson(
        jsonDecode(_string(_key('downloadPreferences')) ?? '{}')
            as Map<String, dynamic>,
      );
    } catch (_) {
      return const DownloadPreferences();
    }
  }

  PlaybackPreferences get playbackPreferences {
    if (locked) return const PlaybackPreferences();
    try {
      return PlaybackPreferences.fromJson(
        jsonDecode(_string(_key('playback')) ?? '{}') as Map<String, dynamic>,
      );
    } catch (_) {
      return const PlaybackPreferences();
    }
  }

  CatalogView get catalogView {
    if (locked) return const CatalogView();
    try {
      return CatalogView.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(_string(_key('catalogView')) ?? '{}') as Map,
        ),
      );
    } catch (_) {
      return const CatalogView();
    }
  }

  List<String> get recentSearches {
    if (locked) return const [];
    try {
      return (jsonDecode(_string(_key('recentSearches')) ?? '[]') as List)
          .whereType<String>()
          .take(20)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> setCatalogView(CatalogView value) =>
      _setting(_key('catalogView'), jsonEncode(value.toJson()));

  Future<void> setCatalogSource(String source, {required bool allSources}) {
    final epoch = _epoch;
    return _queue(() async {
      if (!allowsSource(source) || epoch != _epoch) {
        throw StateError('当前用户没有此站源权限');
      }
      await _commit({
        _key('source'): source,
        _key('catalogView'): jsonEncode(
          catalogView.copyWith(allSources: allSources).toJson(),
        ),
      });
      _notify();
    });
  }

  Future<void> rememberSearch(String text) {
    final query = text.trim();
    if (query.isEmpty || query.runes.length > 80) return Future.value();
    final epoch = _epoch;
    return _queue(() async {
      if (locked || epoch != _epoch) return;
      final entries = [
        query,
        ...recentSearches.where(
          (entry) => normalizedSearchText(entry) != normalizedSearchText(query),
        ),
      ].take(20).toList();
      await _commit({_key('recentSearches'): jsonEncode(entries)});
      _notify();
    });
  }

  Future<void> clearRecentSearches() => _setting(_key('recentSearches'), '[]');

  Future<void> _commit(
    Map<String, Object> changes, {
    Iterable<String> remove = const [],
    bool replace = false,
  }) async {
    final snapshot = _snapshot;
    if (snapshot == null) throw StateError('请先恢复本地配置');
    final values = replace ? <String, Object>{} : snapshot.values;
    for (final key in remove) {
      values.remove(key);
    }
    values.addAll(changes);
    values.putIfAbsent(
      'profiles',
      () => jsonEncode(_profiles.map((profile) => profile.toJson()).toList()),
    );
    values.putIfAbsent('activeProfile', () => _current);
    try {
      await snapshot.commit(values);
    } on SnapshotRecoveryRequired catch (error) {
      _block(error.toString());
      _notify();
      rethrow;
    }
  }

  Future<void> _setting(String key, Object value, {bool admin = false}) {
    final epoch = _epoch;
    return _queue(() async {
      if (admin) _requireAdmin();
      if (locked || epoch != _epoch) throw StateError('当前用户已变更，请重试');
      await _commit({key: value});
      _notify();
    });
  }

  Future<void> setForceLogin(bool value) =>
      _setting('forceLogin', value, admin: true);
  Future<void> setHideVip(bool value) => _setting(_key('hideVip'), value);
  Future<void> setSource(String value) {
    if (!allowsSource(value)) return Future.error(StateError('当前用户没有此站源权限'));
    return _setting(_key('source'), value);
  }

  Future<void> setDisplayMode(String value) =>
      {'auto', 'television', 'phone', 'pad', 'window'}.contains(value)
      ? _setting('displayMode', value)
      : Future.value();
  Future<void> setThemeMode(String value) =>
      {'light', 'dark', 'system'}.contains(value)
      ? _setting('themeMode', value)
      : Future.value();
  Future<void> setFollowSystemColor(bool value) => _queue(() async {
    await preferences.setBool('followSystemColor', value);
    _notify();
  });
  Future<void> setThemeColor(ThemeColor value) => _queue(() async {
    await preferences.setString('themeColor', value.name);
    _notify();
  });
  Future<void> setSideBarExpanded(bool value) => _queue(() async {
    await preferences.setBool('sideBarExpanded', value);
    _notify();
  });
  Future<void> setPlayerWide(bool value) => _queue(() async {
    await preferences.setBool('playerWide', value);
    _notify();
  });
  Future<void> setMiniWindow(
    ({double left, double top, double extent}) value,
  ) => _queue(
    () => preferences.setString(
      'miniWindow',
      '${value.left},${value.top},${value.extent}',
    ),
  );
  Future<void> setTelevisionKeyboard(bool value) => _queue(() async {
    await preferences.setBool('televisionKeyboard', value);
    _notify();
  });
  Future<void> setCheckUpdates(bool value) => _queue(() async {
    await preferences.setBool('checkUpdates', value);
    _notify();
  });
  Future<void> setAutoExport(bool value) => _queue(() async {
    await preferences.setBool('autoExport', value);
    _notify();
  });
  Future<void> setDeleteAfterAutoExport(bool value) => _queue(() async {
    await preferences.setBool('deleteAfterAutoExport', value);
    _notify();
  });
  Future<void> setDeleteAfterManualExport(bool value) => _queue(() async {
    await preferences.setBool('deleteAfterManualExport', value);
    _notify();
  });
  Future<void> setShareUsage(bool value) => _queue(() async {
    await preferences.setBool('shareUsage', value);
    _notify();
  });
  Future<void> setIgnoredUpdate(String version) =>
      _queue(() => preferences.setString('ignoredUpdate', version));
  Future<void> setPlaybackPreferences(PlaybackPreferences value) {
    PlaybackPreferences.fromJson(value.toJson());
    return _setting(_key('playback'), jsonEncode(value.toJson()));
  }

  Future<void> setDownloadPreferences(DownloadPreferences value) {
    DownloadPreferences.fromJson(value.toJson());
    return _setting(_key('downloadPreferences'), jsonEncode(value.toJson()));
  }

  Future<void> toggleFavorite(Drama drama) {
    final epoch = _epoch;
    return _queue(() async {
      if (!allowsSource(drama.source) || epoch != _epoch) return;
      final entries = Map.of(_favorites);
      final states = Map.of(_followStates);
      if (entries.containsKey(drama.id)) {
        entries.remove(drama.id);
        states.remove(drama.id);
      } else {
        if (entries.length >= 20000) throw StateError('追剧数量已达上限，请先整理追剧');
        entries[drama.id] = drama;
        states[drama.id] = FollowState.initial(drama);
      }
      await _commit({
        _key('favorites'): jsonEncode(
          entries.values.map((entry) => entry.toJson()).toList(),
        ),
        _key('followStates'): _encodeFollowStates(states),
      });
      _loadLibrary();
      _notify();
    });
  }

  String _encodeFollowStates(Map<String, FollowState> states) => jsonEncode({
    for (final entry in states.entries) entry.key: entry.value.toJson(),
  });

  Future<void> removeFavorites(Set<String> ids) {
    final epoch = _epoch;
    return _queue(() async {
      if (epoch != _epoch) return;
      final removed = {
        for (final id in ids)
          if (_favorites[id] case final drama? when allowsSource(drama.source))
            id,
      };
      if (removed.isEmpty) return;
      final entries = Map.of(_favorites)
        ..removeWhere((id, _) => removed.contains(id));
      final states = Map.of(_followStates)
        ..removeWhere((id, _) => removed.contains(id));
      await _commit({
        _key('favorites'): jsonEncode(
          entries.values.map((entry) => entry.toJson()).toList(),
        ),
        _key('followStates'): _encodeFollowStates(states),
      });
      _loadLibrary();
      _notify();
    });
  }

  Future<void> markUpdatesRead(String id) {
    final epoch = _epoch;
    return _queue(() async {
      if (!isFavorite(id) || epoch != _epoch) return;
      final states = Map.of(_followStates)
        ..[id] = _followStates[id]!.markRead();
      await _commit({_key('followStates'): _encodeFollowStates(states)});
      _loadLibrary();
      _notify();
    });
  }

  Future<void> markSeriesSeasonRead(String id, String seasonId) {
    final epoch = _epoch;
    return _queue(() async {
      if (!isFavorite(id) || epoch != _epoch) return;
      final current = _followStates[id]!;
      final updated = current.markSeriesSeasonRead(seasonId);
      if (identical(current, updated)) return;
      final states = Map.of(_followStates)..[id] = updated;
      await _commit({_key('followStates'): _encodeFollowStates(states)});
      _loadLibrary();
      _notify();
    });
  }

  Future<void> saveWatch(WatchEntry entry) {
    final epoch = _epoch;
    return _queue(() async {
      if (!allowsSource(entry.drama.source) || epoch != _epoch) return;
      final previous = _history[entry.drama.id]?.drama;
      final current = previous == null
          ? entry
          : WatchEntry(
              drama: previous.merge(entry.drama),
              episode: entry.episode,
              position: entry.position,
              duration: entry.duration,
              updatedAt: entry.updatedAt,
            );
      final entries = Map.of(_history)..[entry.drama.id] = current;
      final sorted = entries.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final following = _followStates[entry.drama.id];
      final states = Map.of(_followStates);
      final favorites = Map.of(_favorites);
      if (following != null) {
        states[entry.drama.id] = following.observe(current.drama);
        favorites[entry.drama.id] = favorites[entry.drama.id]!.merge(
          current.drama,
        );
      }
      await _commit({
        _key('history'): jsonEncode(
          sorted.take(300).map((entry) => entry.toJson()).toList(),
        ),
        if (following != null) ...{
          _key('followStates'): _encodeFollowStates(states),
          _key('favorites'): jsonEncode(
            favorites.values.map((entry) => entry.toJson()).toList(),
          ),
        },
      });
      _loadLibrary();
      _notify();
    });
  }

  WatchEntry? mediaWatched(String id) {
    if (!canDownload) return null;
    try {
      final data = jsonDecode(_string(_key('mediaHistory')) ?? '{}') as Map;
      final entry = data[id] == null
          ? null
          : WatchEntry.fromJson(Map<String, dynamic>.from(data[id] as Map));
      return entry != null && allowsSource(entry.drama.source) ? entry : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveMediaWatch(String id, WatchEntry entry) {
    final epoch = _epoch;
    return _queue(() async {
      if (!canDownload ||
          !allowsSource(entry.drama.source) ||
          epoch != _epoch) {
        return;
      }
      final data = jsonDecode(_string(_key('mediaHistory')) ?? '{}') as Map;
      data.remove(id);
      data[id] = entry.toJson();
      while (data.length > 300) {
        data.remove(data.keys.first);
      }
      await _commit({_key('mediaHistory'): jsonEncode(data)});
    });
  }

  Future<void> clearHistory() {
    final epoch = _epoch;
    return _queue(() async {
      if (locked || epoch != _epoch) return;
      await _commit({}, remove: [_key('history')]);
      _loadLibrary();
      _notify();
    });
  }

  Future<void> removeHistory(Set<String> ids) {
    final epoch = _epoch;
    return _queue(() async {
      if (epoch != _epoch) return;
      final removed = {
        for (final id in ids)
          if (_history[id] case final entry?
              when allowsSource(entry.drama.source))
            id,
      };
      if (removed.isEmpty) return;
      final entries = Map.of(_history)
        ..removeWhere((id, _) => removed.contains(id));
      await _commit({
        _key('history'): jsonEncode(
          entries.values.map((entry) => entry.toJson()).toList(),
        ),
      });
      _loadLibrary();
      _notify();
    });
  }

  Future<void> refreshDrama(Drama drama) =>
      _refreshDramas([drama], cacheSeriesCandidates: false);

  Future<void> refreshDramas(Iterable<Drama> dramas) =>
      _refreshDramas(dramas, cacheSeriesCandidates: true);

  Future<void> _refreshDramas(
    Iterable<Drama> dramas, {
    required bool cacheSeriesCandidates,
  }) {
    final epoch = _epoch;
    final updates = dramas.toList();
    return _queue(() async {
      if (locked || epoch != _epoch) return;
      final changes = <String, Object>{};
      final favorites = Map.of(_favorites);
      final history = Map.of(_history);
      final states = Map.of(_followStates);
      final seriesCandidates = Map.of(_seriesCandidates);
      for (final drama in updates) {
        if (!allowsSource(drama.source)) continue;
        if (cacheSeriesCandidates && drama.source == SourceSite.hongguo.id) {
          seriesCandidates[drama.id] = (seriesCandidates[drama.id] ?? drama)
              .merge(drama);
        }
        final favorite = favorites[drama.id];
        if (favorite != null) {
          favorites[drama.id] = favorite.merge(drama);
          states[drama.id] = states[drama.id]!.observe(favorites[drama.id]!);
        }
        final watched = history[drama.id];
        if (watched != null) {
          history[drama.id] = WatchEntry(
            drama: watched.drama.merge(drama),
            episode: watched.episode,
            position: watched.position,
            duration: watched.duration,
            updatedAt: watched.updatedAt,
          );
        }
      }
      final candidates = <String, Drama>{
        for (final entry in history.values) entry.drama.id: entry.drama,
        ...favorites,
        for (final drama in updates)
          if (allowsSource(drama.source)) drama.id: drama,
      };
      for (final state in states.values) {
        for (final notice in state.seriesSeasons.values) {
          candidates.putIfAbsent(
            notice.id,
            () => Drama(
              id: notice.id,
              source: SourceSite.hongguo.id,
              sourceId: notice.id.substring(SourceSite.hongguo.id.length + 1),
              title: notice.title,
            ),
          );
        }
      }
      final favoriteIds = favorites.keys.toSet();
      for (final favorite in favorites.values) {
        if (favorite.source != SourceSite.hongguo.id ||
            states[favorite.id] == null) {
          continue;
        }
        states[favorite.id] = observeHongguoSeriesSeasons(
          anchor: favorite,
          state: states[favorite.id]!,
          candidates: candidates.values,
          favoriteIds: favoriteIds,
        );
      }
      final favoriteJson = jsonEncode(
        favorites.values.map((entry) => entry.toJson()).toList(),
      );
      final historyJson = jsonEncode(
        history.values.map((entry) => entry.toJson()).toList(),
      );
      final statesJson = _encodeFollowStates(states);
      final cachedCandidates = cacheSeriesCandidates
          ? (seriesCandidates.values.toList()
                  ..sort((a, b) => a.id.compareTo(b.id)))
                .take(2000)
                .toList()
          : null;
      final seriesCandidateJson = cachedCandidates == null
          ? null
          : jsonEncode(
              cachedCandidates.map((entry) => entry.toJson()).toList(),
            );
      if (favoriteJson !=
          jsonEncode(
            _favorites.values.map((entry) => entry.toJson()).toList(),
          )) {
        changes[_key('favorites')] = favoriteJson;
      }
      if (historyJson !=
          jsonEncode(_history.values.map((entry) => entry.toJson()).toList())) {
        changes[_key('history')] = historyJson;
      }
      if (statesJson != _encodeFollowStates(_followStates)) {
        changes[_key('followStates')] = statesJson;
      }
      final seriesChanged =
          seriesCandidateJson != null &&
          seriesCandidateJson != preferences.getString(_seriesKey());
      if (seriesChanged) {
        await preferences.setString(_seriesKey(), seriesCandidateJson);
        _seriesCandidates
          ..clear()
          ..addEntries(
            cachedCandidates!.map((drama) => MapEntry(drama.id, drama)),
          );
      }
      if (changes.isEmpty) {
        if (seriesChanged) _notify();
        return;
      }
      await _commit(changes);
      _loadLibrary();
      _notify();
    });
  }

  void _requireAdmin() {
    if (locked || !profile.admin) throw StateError('仅管理员可以修改此设置');
  }

  Future<void> _checkPin(LocalProfile target, String pin) async {
    if (DateTime.now().isBefore(_retryAfter)) {
      throw StateError('密码输入过于频繁，请稍后再试');
    }
    if (!await checkProfilePin(target, pin)) {
      _failures++;
      if (_failures >= 3) {
        _retryAfter = DateTime.now().add(
          Duration(seconds: (_failures * 2).clamp(0, 30)),
        );
      }
      throw StateError('密码不正确');
    }
    _failures = 0;
  }

  Future<void> switchProfile(String id, {String pin = ''}) => _queue(() async {
    if (_configurationError != null) throw StateError('本地用户配置损坏，请先恢复');
    final target = _profiles.firstWhere((profile) => profile.id == id);
    await _checkPin(target, pin);
    await _commit({'activeProfile': id});
    _current = id;
    _locked = false;
    _loadLibrary();
    _loadSeriesCandidates();
    _epoch++;
    _notify();
  });
  void lock() {
    if (!profile.protected) return;
    _locked = true;
    _epoch++;
    _notify();
  }

  Future<void> saveProfile({
    String? id,
    required String name,
    required List<String> sources,
    required bool download,
    String? pin,
  }) => _queue(() async {
    _requireAdmin();
    final old = _profiles.where((profile) => profile.id == id).firstOrNull;
    final targetId = old?.id ?? randomProfileToken();
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 40) {
      throw StateError('用户名需要 1 至 40 个字符');
    }
    if (sources.any((source) => !SourceSite.isKnown(source))) {
      throw StateError('站源无效');
    }
    if (targetId != 'default' &&
        !_profiles.firstWhere((profile) => profile.admin).protected) {
      throw StateError('请先为管理员设置密码，再创建或修改其他用户');
    }
    if (old == null && _profiles.length >= 20) {
      throw StateError('最多支持 20 个本地用户');
    }
    var salt = old?.salt ?? '', hash = old?.pinHash ?? '';
    if (pin != null) {
      if (pin.isEmpty) {
        if (targetId == 'default' && _profiles.length > 1) {
          throw StateError('存在其他用户时不能取消管理员密码');
        }
        salt = '';
        hash = '';
      } else {
        if (pin.length < 6 || pin.length > 128) {
          throw StateError('密码需要 6 至 128 个字符');
        }
        salt = randomProfileToken();
        hash = await _pinHasher(pin, salt);
      }
    }
    _requireAdmin();
    final updated = LocalProfile(
      id: targetId,
      name: cleanName,
      admin: targetId == 'default',
      sources: sources.toSet().toList(),
      download: download,
      salt: salt,
      pinHash: hash,
    );
    final profiles =
        [
          for (final profile in _profiles)
            if (profile.id != targetId) profile,
          updated,
        ]..sort(
          (a, b) => a.admin
              ? -1
              : b.admin
              ? 1
              : a.name.compareTo(b.name),
        );
    await _commit({
      'profiles': jsonEncode(
        profiles.map((profile) => profile.toJson()).toList(),
      ),
    });
    _profiles = profiles;
    _notify();
  });
  Future<void> deleteProfile(String id) => _queue(() async {
    _requireAdmin();
    if (id == 'default') throw StateError('不能删除管理员');
    final profiles = _profiles.where((profile) => profile.id != id).toList();
    await _commit({
      'profiles': jsonEncode(
        profiles.map((profile) => profile.toJson()).toList(),
      ),
    }, remove: LocalSnapshot.libraryKeys.map((key) => _key(key, id)));
    await preferences.remove(_seriesKey(id));
    await preferences.remove(_followChecksKey(id));
    _profiles = profiles;
    _notify();
  });

  Future<String> exportBackup() async {
    await _writes.catchError((Object _) {});
    _requireAdmin();
    final content = jsonEncode({
      'schema': 1,
      'app': 'zhenguojian',
      'profiles': _profiles.map((profile) => profile.toJson()).toList(),
      'displayMode': displayMode,
      'themeMode': themeMode,
      'followSystemColor': followSystemColor,
      'themeColor': themeColor.name,
      'autoExport': _bool('autoExport') ?? false,
      'exportPosters': _bool('exportPosters') ?? false,
      'forceLogin': forceLogin,
      'libraries': {
        for (final profile in _profiles)
          profile.id: {
            'history': readJsonList(_string(_key('history', profile.id))),
            'favorites': readJsonList(_string(_key('favorites', profile.id))),
            'followStates': jsonDecode(
              _string(_key('followStates', profile.id)) ?? '{}',
            ),
            'seriesCandidates': readJsonList(
              preferences.getString(_seriesKey(profile.id)) ??
                  _string(_key('seriesCandidates', profile.id)),
            ),
            'mediaHistory': jsonDecode(
              _string(_key('mediaHistory', profile.id)) ?? '{}',
            ),
            'source': _string(_key('source', profile.id)) ?? '',
            'hideVip': _bool(_key('hideVip', profile.id)) ?? true,
            'playback': jsonDecode(
              _string(_key('playback', profile.id)) ?? '{}',
            ),
            'downloadPreferences': jsonDecode(
              _string(_key('downloadPreferences', profile.id)) ?? '{}',
            ),
            'catalogView': jsonDecode(
              _string(_key('catalogView', profile.id)) ?? '{}',
            ),
            'recentSearches': jsonDecode(
              _string(_key('recentSearches', profile.id)) ?? '[]',
            ),
          },
      },
    });
    if (utf8.encode(content).length > 8 * 1024 * 1024) {
      throw StateError('备份超过 8 MiB 保存上限，请先整理记录；尚未写出备份文件');
    }
    validateBackup(content);
    return content;
  }

  Map<String, dynamic> validateBackup(String content) {
    if (utf8.encode(content).length > 8 * 1024 * 1024) {
      throw const FormatException('备份文件过大');
    }
    final data = jsonDecode(content) as Map<String, dynamic>;
    if (data['schema'] != 1 || data['app'] != 'zhenguojian') {
      throw const FormatException('不支持的备份格式');
    }
    final profiles = _readProfiles(data['profiles']);
    if (data.containsKey('themeMode') &&
        !{'light', 'dark', 'system'}.contains(data['themeMode'])) {
      throw const FormatException('备份主题设置无效');
    }
    if (data.containsKey('followSystemColor') &&
            data['followSystemColor'] is! bool ||
        data.containsKey('themeColor') &&
            ThemeColor.byName(data['themeColor']) == null) {
      throw const FormatException('备份主题色设置无效');
    }
    if (data.containsKey('forceLogin') && data['forceLogin'] is! bool) {
      throw const FormatException('备份登录设置无效');
    }
    final libraries = data['libraries'] as Map;
    for (final profile in profiles) {
      final library = libraries[profile.id] as Map;
      final history = library['history'] as List,
          favorites = library['favorites'] as List;
      final media = library['mediaHistory'] as Map? ?? {};
      if (media.length > 300 ||
          history.length > 300 ||
          favorites.length > 20000) {
        throw const FormatException('备份记录过多');
      }
      for (final row in [...history, ...media.values]) {
        WatchEntry.fromJson(Map<String, dynamic>.from(row as Map));
      }
      for (final row in favorites) {
        Drama.fromJson(Map<String, dynamic>.from(row as Map));
      }
      final states = library['followStates'] as Map? ?? {};
      final seriesCandidates = library['seriesCandidates'] as List? ?? [];
      final favoriteIds = favorites.map((row) => (row as Map)['id']).toSet();
      if (states.length > 20000 ||
          states.keys.any((id) => id is! String || !favoriteIds.contains(id))) {
        throw const FormatException('备份追剧状态无效');
      }
      for (final row in states.values) {
        FollowState.fromJson(Map<String, dynamic>.from(row as Map));
      }
      if (seriesCandidates.length > 2000) {
        throw const FormatException('备份系列候选过多');
      }
      for (final row in seriesCandidates) {
        Drama.fromJson(Map<String, dynamic>.from(row as Map));
      }
      if (library['hideVip'] is! bool || library['source'] is! String) {
        throw const FormatException('备份设置无效');
      }
      PlaybackPreferences.fromJson(
        Map<String, dynamic>.from(library['playback'] as Map? ?? {}),
      );
      DownloadPreferences.fromJson(
        Map<String, dynamic>.from(library['downloadPreferences'] as Map? ?? {}),
      );
      CatalogView.fromJson(
        Map<String, dynamic>.from(library['catalogView'] as Map? ?? {}),
      );
      final searches = library['recentSearches'] as List? ?? [];
      if (searches.length > 20 ||
          searches.any(
            (value) => value is! String || value.runes.length > 80,
          )) {
        throw const FormatException('备份搜索记录无效');
      }
    }
    return data;
  }

  Future<void> _installBackup(Map<String, dynamic> data) async {
    final profiles = _readProfiles(data['profiles']);
    final values = <String, Object>{
      'profiles': jsonEncode(
        profiles.map((profile) => profile.toJson()).toList(),
      ),
      'activeProfile': profiles.firstWhere((profile) => profile.admin).id,
      'displayMode':
          {
            'auto',
            'television',
            'phone',
            'pad',
            'window',
          }.contains(data['displayMode'])
          ? data['displayMode'] as String
          : 'auto',
      'themeMode': data['themeMode'] as String? ?? themeMode,
      'autoExport': data['autoExport'] == true,
      'exportPosters': data['exportPosters'] == true,
      'forceLogin': data['forceLogin'] is bool
          ? data['forceLogin'] as bool
          : profiles.firstWhere((profile) => profile.admin).protected,
    };
    final libraries = data['libraries'] as Map;
    for (final profile in profiles) {
      final library = libraries[profile.id] as Map;
      values.addAll({
        _key('history', profile.id): jsonEncode(library['history']),
        _key('favorites', profile.id): jsonEncode(library['favorites']),
        _key('followStates', profile.id): jsonEncode(
          library['followStates'] ?? {},
        ),
        _key('mediaHistory', profile.id): jsonEncode(
          library['mediaHistory'] ?? {},
        ),
        _key('source', profile.id): library['source'] as String,
        _key('hideVip', profile.id): library['hideVip'] as bool,
        _key('playback', profile.id): jsonEncode(library['playback'] ?? {}),
        _key('downloadPreferences', profile.id): jsonEncode(
          library['downloadPreferences'] ?? {},
        ),
        _key('catalogView', profile.id): jsonEncode(
          library['catalogView'] ?? {},
        ),
        _key('recentSearches', profile.id): jsonEncode(
          library['recentSearches'] ?? [],
        ),
      });
    }
    await _commit(values, replace: true);
    if (data['followSystemColor'] case final bool follow) {
      await preferences.setBool('followSystemColor', follow);
    }
    if (ThemeColor.byName(data['themeColor']) case final color?) {
      await preferences.setString('themeColor', color.name);
    }
    for (final key in preferences.getKeys().toList()) {
      if (key.startsWith('seriesCandidates.')) await preferences.remove(key);
    }
    for (final profile in profiles) {
      await preferences.setString(
        _seriesKey(profile.id),
        jsonEncode((libraries[profile.id] as Map)['seriesCandidates'] ?? []),
      );
    }
    _profiles = profiles;
    _current = profiles.firstWhere((profile) => profile.admin).id;
    _configurationError = null;
    _locked = forceLogin && profile.protected;
    _loadSourceSwitches();
    _loadLibrary();
    _loadSeriesCandidates();
    _epoch++;
    _notify();
  }

  Future<void> importBackup(String content) => _queue(() async {
    _requireAdmin();
    await _installBackup(validateBackup(content));
  });

  Future<void> recoverBackup(String content, {required String pin}) =>
      _queue(() async {
        if (_configurationError == null) throw StateError('请从设置中恢复备份');
        final data = validateBackup(content);
        LocalProfile? originalAdmin;
        try {
          final raw = preferences.getString(LocalSnapshot.storageKey);
          final values = raw == null
              ? null
              : (jsonDecode(raw) as Map)['values'] as Map;
          final records =
              jsonDecode(
                    (values?['profiles'] as String?) ??
                        preferences.getString('profiles') ??
                        '[]',
                  )
                  as List;
          for (final row in records) {
            if (row is Map && row['admin'] == true) {
              originalAdmin = LocalProfile.fromJson(
                Map<String, dynamic>.from(row),
              );
            }
          }
        } catch (_) {}
        final backupAdmin = _readProfiles(
          data['profiles'],
        ).firstWhere((profile) => profile.admin);
        final verifier = originalAdmin?.protected == true
            ? originalAdmin!
            : backupAdmin;
        if (!verifier.protected) throw StateError('无法验证管理员身份，请使用包含管理员密码的备份恢复');
        await _checkPin(verifier, pin);
        _snapshot ??= LocalSnapshot.empty(preferences);
        await _installBackup(data);
      });

  String exportRecoveryData() {
    if (_configurationError == null) throw StateError('请从设置中导出备份');
    return jsonEncode({
      'app': 'zhenguojian',
      'recovery': true,
      'values': {
        for (final key in preferences.getKeys())
          if (LocalSnapshot.owns(key) || key == LocalSnapshot.storageKey)
            key: preferences.get(key),
      },
    });
  }

  Future<void> reload() => _queue(() async {
    final previousProfiles = _configurationError == null
        ? _string('profiles')
        : null;
    final previousId = _current;
    final previousLocked = locked;
    await preferences.reload();
    _initialize();
    if (_configurationError == null &&
        previousProfiles == _string('profiles') &&
        previousId == _current) {
      _locked = previousLocked;
    } else {
      _epoch++;
    }
    _notify();
  });

  Future<void> _queue(Future<void> Function() action) {
    _writes = _writes.catchError((Object _) {}).then((_) => action());
    return _writes;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
