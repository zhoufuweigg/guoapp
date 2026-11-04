/// 站源目录浏览断点。
///
/// 记录用户在每个源的视频列表里刷到的位置：断点处视频的编号（id）与名称，
/// 以及周围视频的 id 列表。目录顺序变化时，若断点视频本身已不存在，
/// 可经相邻视频重新锚定到附近位置。
class CatalogProgress {
  const CatalogProgress({
    required this.dramaId,
    required this.dramaTitle,
    required this.neighbors,
    required this.updatedAt,
  });

  /// 断点处视频 id（目录条目主键）
  final String dramaId;

  /// 断点处视频名称（用于恢复提示与兜底匹配）
  final String dramaTitle;

  /// 断点前后相邻视频 id（去重、限长），用于目录变动后重新锚定
  final List<String> neighbors;

  /// 最近一次滚动到该位置的时间（epoch 毫秒）
  final int updatedAt;

  /// 相邻视频最多保留的条数（前后合计）
  static const maxNeighbors = 24;

  Map<String, dynamic> toJson() => {
    'dramaId': dramaId,
    'dramaTitle': dramaTitle,
    'neighbors': neighbors,
    'updatedAt': updatedAt,
  };

  /// 从备份/本地 JSON 解析；数据不完整时返回 null 由调用方丢弃。
  static CatalogProgress? fromJson(Object? value) {
    if (value is! Map) return null;
    final dramaId = (value['dramaId'] as String?)?.trim() ?? '';
    if (dramaId.isEmpty || dramaId.length > 128) return null;
    final title = (value['dramaTitle'] as String?) ?? '';
    final neighbors = (value['neighbors'] as List? ?? const [])
        .whereType<String>()
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && id != dramaId && id.length <= 128)
        .toSet()
        .take(maxNeighbors)
        .toList();
    return CatalogProgress(
      dramaId: dramaId,
      dramaTitle: title.length > 256 ? title.substring(0, 256) : title,
      neighbors: neighbors,
      updatedAt: (value['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  /// 由当前目录列表与断点索引构造；neighbors 取断点前后各若干条。
  static CatalogProgress capture({
    required List<String> ids,
    required List<String> titles,
    required int index,
    required int now,
    int side = 3,
  }) {
    final dramaId = ids[index];
    final dramaTitle = titles[index];
    final neighbors = <String>[];
    for (var step = 1; step <= side; step++) {
      final before = index - step;
      if (before >= 0 && ids[before] != dramaId) neighbors.add(ids[before]);
      final after = index + step;
      if (after < ids.length && ids[after] != dramaId)
        neighbors.add(ids[after]);
    }
    return CatalogProgress(
      dramaId: dramaId,
      dramaTitle: dramaTitle,
      neighbors: neighbors,
      updatedAt: now,
    );
  }
}

/// 浏览进度备份的字段数量上限。
///
/// 断点按「源分组 + 二级分类」分别存储（如 `hongguo:app:recommendations:short_play`），
/// 上限相应放宽；超出时丢弃最旧的断点。
const catalogProgressMaxEntries = 256;
