import 'dart:convert';

import 'package:duanju_app/app_build.dart';
import 'package:duanju_app/local_profiles.dart';
import 'package:duanju_app/local_snapshot.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Map<String, Object> _viewer(List<String> sources) => {
  'profiles': jsonEncode([
    LocalProfile(
      id: 'default',
      name: '管理员',
      admin: true,
      salt: '0' * 32,
      pinHash: '1' * 64,
    ).toJson(),
    LocalProfile(
      id: 'viewer',
      name: '访客',
      sources: sources,
      download: false,
    ).toJson(),
  ]),
  'activeProfile': 'viewer',
};

Future<LocalStore> _withVisitor() async {
  final store = await openStore();
  await store.saveProfile(
    id: 'default',
    name: '管理员',
    sources: [],
    download: true,
    pin: 'abcdef12',
  );
  await store.saveProfile(name: '访客', sources: ['hongguo'], download: false);
  return store;
}

void main() {
  final hongguo = drama('1', title: '红果剧');
  final huangdou = drama('2', source: 'huangdou', title: '黄豆剧');

  group('profiles', () {
    test('users need an administrator password first', () async {
      final store = await openStore();
      await expectLater(
        store.saveProfile(name: '访客', sources: ['hongguo'], download: false),
        throwsStateError,
      );
      await store.saveProfile(
        id: 'default',
        name: '管理员',
        sources: [],
        download: true,
        pin: 'abcdef12',
      );
      await store.saveProfile(name: '访客', sources: [], download: false);
      expect(store.profiles, hasLength(2));
      expect(
        store.preferences.getString(LocalSnapshot.storageKey),
        isNot(contains('abcdef12')),
      );
    });

    test('each user sees only their own records and sources', () async {
      final store = await _withVisitor();
      await store.toggleFavorite(hongguo);
      final visitor = store.profiles.firstWhere((profile) => !profile.admin);
      await store.switchProfile(visitor.id);

      expect(store.favorites, isEmpty);
      expect(store.sources.map((site) => site.id), ['hongguo']);
      expect(store.canDownload, isFalse);
      await store.toggleFavorite(huangdou);
      expect(store.favorites, isEmpty);
      await expectLater(
        store.setSourceEnabled('hongguo', false),
        throwsStateError,
      );

      await expectLater(
        store.switchProfile('default', pin: 'wrong'),
        throwsStateError,
      );
      expect(store.profile.id, visitor.id);
      await store.switchProfile('default', pin: 'abcdef12');
      expect(store.favorites.single.id, hongguo.id);
    });

    test('a protected administrator is locked after restart', () async {
      final store = await _withVisitor();
      expect(store.forceLogin, isTrue);

      final restarted = restartStore(store);
      expect(restarted.locked, isTrue);
      expect(restarted.sources, isEmpty);
      expect(restarted.canDownload, isFalse);
      await restarted.switchProfile('default', pin: 'abcdef12');
      expect(restarted.canDownload, isTrue);
      await restarted.setForceLogin(false);

      final unlocked = restartStore(restarted);
      expect(unlocked.locked, isFalse);
      unlocked.lock();
      expect(unlocked.locked, isTrue);
    });

    test('repeated wrong passwords pause further attempts', () async {
      final store = await _withVisitor();
      store.lock();
      for (var attempt = 0; attempt < 3; attempt++) {
        await expectLater(
          store.switchProfile('default', pin: 'wrong'),
          throwsA(
            isA<StateError>().having((e) => e.message, 'message', '密码不正确'),
          ),
        );
      }
      await expectLater(
        store.switchProfile('default', pin: 'abcdef12'),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', contains('频繁')),
        ),
      );
      expect(store.locked, isTrue);
    });
  });

  group('sources', () {
    test('restricted sources start switched off', () async {
      final store = await openStore();
      expect(
        store.sources.map((site) => site.id),
        allSourcesEnabled
            ? ['hongguo', 'hanxiaoquan', 'guipian', 'sorani']
            : ['hongguo'],
      );
      for (final site in SourceSite.restrictedValues) {
        expect(store.sourceEnabled(site.id), isFalse, reason: site.id);
        expect(store.allowsSource(site.id), isFalse, reason: site.id);
      }
    });

    test('switches persist and follow the build edition', () async {
      final store = await openStore();
      await store.setSourceEnabled('hongguo', false);
      if (allSourcesEnabled) {
        await store.setSourceEnabled('dsd', true);
      } else {
        await expectLater(
          store.setSourceEnabled('dsd', true),
          throwsStateError,
        );
      }

      final restarted = restartStore(store);
      expect(restarted.allowsSource('hongguo'), isFalse);
      expect(restarted.allowsSource('dsd'), allSourcesEnabled);
      expect(restarted.source, allSourcesEnabled ? 'hanxiaoquan' : '');
    });

    for (final source in ['huangdou', 'dsd']) {
      test('a restored $source user keeps identity across editions', () async {
        final store = await openStore({
          ..._viewer([source]),
          'sourceSwitches': jsonEncode({source: true}),
          'profile.viewer.source': source,
        });
        expect(store.configurationError, isNull);
        expect(store.profile.id, 'viewer');
        expect(store.profile.sources, [source]);
        expect(store.allowsSource(source), allSourcesEnabled);
        expect(store.allowsSource('hongguo'), isFalse);
        expect(store.source, allSourcesEnabled ? source : '');
      });
    }
  });

  test('build edition names match the source list', () {
    expect(appSlug, allSourcesEnabled ? 'zhenguojian' : 'hongguojian');
    expect(appName, allSourcesEnabled ? '真果鉴' : '红果鉴');
    expect(
      SourceSite.values.map((site) => site.id),
      allSourcesEnabled
          ? SourceSite.allValues.map((site) => site.id)
          : ['hongguo'],
    );
    expect(SourceSite.isKnown('dsd'), isTrue);
    expect(SourceSite.isAvailable('dsd'), allSourcesEnabled);
  });
}
