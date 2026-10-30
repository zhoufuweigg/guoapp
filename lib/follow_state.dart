import 'dart:math';

import 'models.dart';

class FollowState {
  const FollowState({
    this.knownEpisodes = 0,
    this.readEpisodes,
    this.seriesSeasons = const {},
  });

  final int knownEpisodes;
  final int? readEpisodes;
  final Map<String, SeriesSeasonNotice> seriesSeasons;

  int get newEpisodes =>
      readEpisodes == null ? 0 : max(0, knownEpisodes - readEpisodes!);
  bool get hasUpdates => newEpisodes > 0;

  FollowState copyWith({
    int? knownEpisodes,
    int? readEpisodes,
    Map<String, SeriesSeasonNotice>? seriesSeasons,
  }) => FollowState(
    knownEpisodes: knownEpisodes ?? this.knownEpisodes,
    readEpisodes: readEpisodes ?? this.readEpisodes,
    seriesSeasons: seriesSeasons ?? this.seriesSeasons,
  );

  factory FollowState.initial(Drama drama) {
    final count = max(0, drama.episodes);
    return FollowState(
      knownEpisodes: count,
      readEpisodes: count > 0 ? count : null,
    );
  }

  FollowState observe(Drama drama) {
    final count = max(knownEpisodes, drama.episodes);
    return FollowState(
      knownEpisodes: count,
      readEpisodes: readEpisodes ?? (count > 0 ? count : null),
      seriesSeasons: seriesSeasons,
    );
  }

  FollowState markRead() => FollowState(
    knownEpisodes: knownEpisodes,
    readEpisodes: knownEpisodes > 0 ? knownEpisodes : null,
    seriesSeasons: seriesSeasons,
  );

  FollowState markSeriesSeasonRead(String id) =>
      seriesSeasons[id]?.read != false
      ? this
      : copyWith(
          seriesSeasons: Map.of(seriesSeasons)
            ..[id] = seriesSeasons[id]!.markRead(),
        );

  Map<String, dynamic> toJson() {
    final value = <String, dynamic>{
      'knownEpisodes': knownEpisodes,
      'readEpisodes': readEpisodes,
    };
    if (seriesSeasons.isNotEmpty) {
      value['seriesSeasons'] = {
        for (final entry in seriesSeasons.entries)
          entry.key: entry.value.toJson(),
      };
    }
    return value;
  }

  factory FollowState.fromJson(Map<String, dynamic> json) {
    final known = json['knownEpisodes'];
    final read = json['readEpisodes'];
    final rawSeasons = json['seriesSeasons'];
    final seasons = <String, SeriesSeasonNotice>{};
    if (rawSeasons != null) {
      if (rawSeasons is! Map || rawSeasons.length > 200) {
        throw const FormatException('系列剧提醒无效');
      }
      for (final entry in rawSeasons.entries) {
        if (entry.key is! String) throw const FormatException('系列剧提醒无效');
        if (entry.value is! Map) throw const FormatException('系列剧提醒无效');
        final notice = SeriesSeasonNotice.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (entry.key != notice.id || seasons.containsKey(notice.id)) {
          throw const FormatException('系列剧提醒无效');
        }
        seasons[notice.id] = notice;
      }
    }
    if (known is! int ||
        known < 0 ||
        known > 1000000 ||
        read != null && (read is! int || read < 0 || read > known)) {
      throw const FormatException('追剧状态无效');
    }
    return FollowState(
      knownEpisodes: known,
      readEpisodes: read as int?,
      seriesSeasons: seasons,
    );
  }
}

class SeriesSeasonNotice {
  const SeriesSeasonNotice({
    required this.id,
    required this.title,
    required this.season,
    required this.unit,
    this.read = false,
  });

  final String id;
  final String title;
  final int season;
  final String unit;
  final bool read;

  SeriesSeasonNotice markRead() => read
      ? this
      : SeriesSeasonNotice(
          id: id,
          title: title,
          season: season,
          unit: unit,
          read: true,
        );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'season': season,
    'unit': unit,
    'read': read,
  };

  factory SeriesSeasonNotice.fromJson(Map<String, dynamic> json) {
    final id = json['id'], title = json['title'], season = json['season'];
    final unit = json['unit'], read = json['read'];
    if (id is! String ||
        !id.startsWith('${SourceSite.hongguo.id}:') ||
        id.length > 512 ||
        title is! String ||
        title.trim().isEmpty ||
        title.length > 300 ||
        season is! int ||
        season < 1 ||
        season > 200 ||
        unit is! String ||
        !{'季', '部'}.contains(unit) ||
        read is! bool) {
      throw const FormatException('系列剧提醒无效');
    }
    return SeriesSeasonNotice(
      id: id,
      title: title,
      season: season,
      unit: unit,
      read: read,
    );
  }
}

class FollowCheck {
  const FollowCheck(this.checkedAt, {this.failures = 0});

  final DateTime checkedAt;
  final int failures;

  List<int> toJson() => [checkedAt.millisecondsSinceEpoch, failures];

  factory FollowCheck.fromJson(Object? json) {
    if (json is! List ||
        json.length != 2 ||
        json[0] is! int ||
        json[1] is! int ||
        (json[1] as int) < 0) {
      throw const FormatException('追剧检查记录无效');
    }
    return FollowCheck(
      DateTime.fromMillisecondsSinceEpoch(json[0] as int),
      failures: json[1] as int,
    );
  }
}

int resumeEpisodeIndex(List<Episode> episodes, WatchEntry? watch) {
  if (episodes.isEmpty || watch == null) return 0;
  final current = episodes.indexWhere((item) => item.number == watch.episode);
  if (current >= 0 && !watch.finished) return current;
  final next = episodes.indexWhere((item) => item.number > watch.episode);
  if (next >= 0) return next;
  return current >= 0 ? current : episodes.length - 1;
}
