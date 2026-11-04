import 'dart:convert';

import 'package:duanju_app/catalog_progress.dart';
import 'package:duanju_app/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(LocalStore, InMemorySharedPreferencesStore)> create([
    Map<String, Object> initial = const {},
  ]) async {
    SharedPreferences.resetStatic();
    final platform = InMemorySharedPreferencesStore.withData({
      for (final entry in initial.entries) 'flutter.${entry.key}': entry.value,
    });
    SharedPreferencesStorePlatform.instance = platform;
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    return (store, platform);
  }

  Future<LocalStore> restart(InMemorySharedPreferencesStore platform) async {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = platform;
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    return store;
  }

  group('CatalogProgress', () {
    test('capture 记录断点视频与前后邻居', () {
      final ids = List.generate(10, (i) => 'd$i');
      final titles = List.generate(10, (i) => '剧$i');
      final progress = CatalogProgress.capture(
        ids: ids,
        titles: titles,
        index: 4,
        now: 1700000000000,
      );
      expect(progress.dramaId, 'd4');
      expect(progress.dramaTitle, '剧4');
      expect(progress.neighbors, ['d3', 'd5', 'd2', 'd6', 'd1', 'd7']);
      expect(progress.updatedAt, 1700000000000);
    });

    test('toJson/fromJson 往返一致', () {
      final progress = CatalogProgress.capture(
        ids: const ['a', 'b', 'c', 'd'],
        titles: const ['甲', '乙', '丙', '丁'],
        index: 1,
        now: 42,
      );
      final restored = CatalogProgress.fromJson(progress.toJson());
      expect(restored, isNotNull);
      expect(restored!.dramaId, progress.dramaId);
      expect(restored.dramaTitle, progress.dramaTitle);
      expect(restored.neighbors, progress.neighbors);
      expect(restored.updatedAt, 42);
    });

    test('fromJson 拒绝无效数据并清理邻居', () {
      expect(CatalogProgress.fromJson(null), isNull);
      expect(CatalogProgress.fromJson('x'), isNull);
      expect(CatalogProgress.fromJson(const {}), isNull);
      final parsed = CatalogProgress.fromJson(const {
        'dramaId': 'd1',
        'neighbors': ['d1', 'd2', 'd2', '', 'd3'],
        'updatedAt': 7,
      });
      expect(parsed!.neighbors, ['d2', 'd3']);
      final overflow = CatalogProgress.fromJson({
        'dramaId': 'x' * 200,
      });
      expect(overflow, isNull);
    });
  });

  group('LocalStore 浏览进度', () {
    test('保存、读取、重启保留与清除', () async {
      final (store, platform) = await create();
      expect(store.catalogProgress, isEmpty);
      await store.saveCatalogProgress(
        'hongguo',
        CatalogProgress.capture(
          ids: const ['a', 'b', 'c', 'd', 'e'],
          titles: const ['甲', '乙', '丙', '丁', '戊'],
          index: 2,
          now: 1000,
        ),
      );
      await store.saveCatalogProgress(
        'all',
        const CatalogProgress(dramaId: 'z', dramaTitle: '杂', neighbors: [], updatedAt: 2000),
      );
      expect(store.catalogProgress.length, 2);
      expect(store.catalogProgress['hongguo']!.dramaId, 'c');
      final restarted = await restart(platform);
      expect(restarted.catalogProgress.length, 2);
      expect(restarted.catalogProgress['all']!.updatedAt, 2000);
      await restarted.clearCatalogProgress();
      expect(restarted.catalogProgress, isEmpty);
      expect((await restart(platform)).catalogProgress, isEmpty);
    });

    test('saveCatalogProgress(null) 仅删除指定源', () async {
      final (store, _) = await create();
      await store.saveCatalogProgress(
        'hongguo',
        const CatalogProgress(dramaId: 'a', dramaTitle: '甲', neighbors: [], updatedAt: 1),
      );
      await store.saveCatalogProgress(
        'yeguo',
        const CatalogProgress(dramaId: 'b', dramaTitle: '乙', neighbors: [], updatedAt: 2),
      );
      await store.saveCatalogProgress('hongguo', null);
      expect(store.catalogProgress.keys, ['yeguo']);
    });

    test('「源分组+二级分类」复合键各自独立存储', () async {
      final (store, platform) = await create();
      // 同一源下的不同二级分类（含红果推荐视图的细分类）互不覆盖
      await store.saveCatalogProgress(
        'hongguo:',
        CatalogProgress.capture(
          ids: const ['a', 'b', 'c'],
          titles: const ['甲', '乙', '丙'],
          index: 0,
          now: 1000,
        ),
      );
      await store.saveCatalogProgress(
        'hongguo:theme:xxx',
        CatalogProgress.capture(
          ids: const ['d', 'e', 'f'],
          titles: const ['丁', '戊', '己'],
          index: 2,
          now: 2000,
        ),
      );
      await store.saveCatalogProgress(
        'hongguo:app:recommendations:short_play',
        CatalogProgress.capture(
          ids: const ['g', 'h'],
          titles: const ['庚', '辛'],
          index: 1,
          now: 3000,
        ),
      );
      expect(store.catalogProgress.length, 3);
      expect(store.catalogProgress['hongguo:']!.dramaId, 'a');
      expect(store.catalogProgress['hongguo:theme:xxx']!.dramaId, 'f');
      expect(
        store.catalogProgress['hongguo:app:recommendations:short_play']!.dramaId,
        'h',
      );
      final restarted = await restart(platform);
      expect(restarted.catalogProgress.length, 3);
      expect(restarted.catalogProgress['hongguo:theme:xxx']!.updatedAt, 2000);
    });

    test('超出条目上限时淘汰最旧的断点', () async {
      final (store, _) = await create();
      for (var i = 0; i < 260; i++) {
        await store.saveCatalogProgress(
          'key$i',
          CatalogProgress(dramaId: 'd$i', dramaTitle: '剧$i', neighbors: [], updatedAt: i),
        );
      }
      expect(store.catalogProgress.length, 256);
      // 最旧的 4 条（key0..key3）被淘汰，最新的保留
      expect(store.catalogProgress.containsKey('key0'), isFalse);
      expect(store.catalogProgress.containsKey('key3'), isFalse);
      expect(store.catalogProgress.containsKey('key4'), isTrue);
      expect(store.catalogProgress.containsKey('key259'), isTrue);
    });

    test('备份导出包含浏览进度，恢复后生效', () async {
      final (store, platform) = await create();
      await store.saveCatalogProgress(
        'hongguo',
        CatalogProgress.capture(
          ids: const ['a', 'b', 'c', 'd', 'e'],
          titles: const ['甲', '乙', '丙', '丁', '戊'],
          index: 3,
          now: 1000,
        ),
      );
      final backup = jsonDecode(await store.exportBackup())
          as Map<String, dynamic>;
      final library = (backup['libraries'] as Map)['default'] as Map;
      final progress = library['catalogProgress'] as Map;
      expect((progress['hongguo'] as Map)['dramaId'], 'd');
      // 篡改断点后恢复
      (progress['hongguo'] as Map)['dramaId'] = 'e';
      await store.importBackup(jsonEncode(backup));
      final restored = await restart(platform);
      expect(restored.catalogProgress['hongguo']!.dramaId, 'e');
    });

    test('旧备份（无 catalogProgress 字段）兼容导入', () async {
      final (store, _) = await create();
      final backup = jsonDecode(await store.exportBackup())
          as Map<String, dynamic>;
      ((backup['libraries'] as Map)['default'] as Map)
          .remove('catalogProgress');
      await store.importBackup(jsonEncode(backup));
      expect(store.catalogProgress, isEmpty);
    });

    test('无效浏览进度的备份被拒绝', () async {
      final (store, _) = await create();
      final before = await store.exportBackup();
      final backup = jsonDecode(before) as Map<String, dynamic>;
      ((backup['libraries'] as Map)['default'] as Map)['catalogProgress'] = {
        'hongguo': 'not-a-map',
      };
      await expectLater(
        store.importBackup(jsonEncode(backup)),
        throwsA(isA<FormatException>()),
      );
      expect(await store.exportBackup(), before);
    });
  });

  group('PlaybackPreferences 浏览进度开关', () {
    test('默认开启且可持久化', () async {
      final (store, platform) = await create();
      expect(store.playbackPreferences.saveCatalogProgress, isTrue);
      expect(store.playbackPreferences.keepSpeedLockAcrossEpisodes, isTrue);
      await store.setPlaybackPreferences(
        store.playbackPreferences.copyWith(saveCatalogProgress: false),
      );
      final restarted = await restart(platform);
      expect(restarted.playbackPreferences.saveCatalogProgress, isFalse);
      // 旧配置（无该字段）回退默认开启
      SharedPreferences.resetStatic();
      final legacy = InMemorySharedPreferencesStore.withData(const {});
      SharedPreferencesStorePlatform.instance = legacy;
      final legacyStore = LocalStore(await SharedPreferences.getInstance());
      addTearDown(legacyStore.dispose);
      expect(legacyStore.playbackPreferences.saveCatalogProgress, isTrue);
    });
  });
}
