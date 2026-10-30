import 'dart:convert';

import 'package:duanju_app/app_build.dart';
import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/local_profiles.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

List<Future<Object?> Function()> _requests(
  NativeRepository repository,
  Drama drama,
) {
  final episode = Episode({'id': '1'}, 1);
  return [
    () => repository.catalog(drama.source),
    () => repository.cached(drama.source),
    () => repository.categories(drama.source),
    () => repository.detail(drama),
    () => repository.cover(drama),
    () => repository.resolve(drama, episode),
    () => repository.enqueueDownloads(DramaDetail(drama, [episode]), [episode]),
    () => repository.localPlayback(drama, episode),
  ];
}

Matcher _failure(Object message) => throwsA(
  isA<AppFailure>().having((failure) => failure.message, 'message', message),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sources outside this edition never reach the native core', () async {
    final repository = NativeRepository(background: true);
    for (final source in [
      ...SourceSite.allValues
          .where((site) => !SourceSite.isAvailable(site.id))
          .map((site) => site.id),
      'unknown',
    ]) {
      for (final request in _requests(repository, drama('1', source: source))) {
        await expectLater(request(), _failure('当前版本不包含此站源'));
      }
    }
  });

  test('a user without the source or downloads is stopped first', () async {
    final store = await openStore({
      'profiles': jsonEncode([
        LocalProfile(
          id: 'default',
          name: '管理员',
          admin: true,
          salt: '0' * 32,
          pinHash: '1' * 64,
        ).toJson(),
        const LocalProfile(
          id: 'viewer',
          name: '只看红果',
          sources: ['hongguo'],
          download: false,
        ).toJson(),
      ]),
      'activeProfile': 'viewer',
    });
    final repository = NativeRepository()..access = store;
    expect(repository.supportsDownloads, isFalse);

    final denied = drama('2', source: 'huangdou');
    for (final request in _requests(repository, denied)) {
      await expectLater(
        request(),
        _failure(allSourcesEnabled ? '当前用户没有此操作权限' : '当前版本不包含此站源'),
      );
    }
    final allowed = drama('1');
    final episode = Episode({'id': '1'}, 1);
    for (final request in [
      () => repository.enqueueDownloads(DramaDetail(allowed, [episode]), [
        episode,
      ]),
      () => repository.localPlayback(allowed, episode),
    ]) {
      await expectLater(request(), _failure('当前用户没有此操作权限'));
    }
    await expectLater(repository.downloads(), _failure('当前用户仅支持在线观看'));
  });

  test('a locked administrator is stopped before any request', () async {
    final store = await openStore({
      'profiles': jsonEncode([
        LocalProfile(
          id: 'default',
          name: '管理员',
          admin: true,
          salt: '0' * 32,
          pinHash: '1' * 64,
        ).toJson(),
      ]),
    });
    expect(store.locked, isTrue);
    final repository = NativeRepository()..access = store;
    await expectLater(repository.catalog('hongguo'), _failure('请先解锁当前用户'));
  });
}
