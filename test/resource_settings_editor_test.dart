import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/resource_settings.dart';
import 'package:duanju_app/resource_settings_editor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class _FailingRepository extends FakeRepository {
  @override
  Future<ResourceSettings> saveResourceSettings(ResourceSettings settings) =>
      Future.error(AppFailure('保存失败'));
}

void main() {
  test('admins load and save, the saved copy replaces the local one', () async {
    final repository = FakeRepository()
      ..resource = const ResourceSettings(catalogConcurrency: 4);
    final editor = ResourceSettingsEditor(repository, await openStore());
    addTearDown(editor.dispose);

    await editor.load();
    expect(editor.settings?.catalogConcurrency, 4);

    await editor.save(editor.settings!.copyWith(catalogIntervalMs: 1000));
    expect(repository.savedResources.single.catalogIntervalMs, 1000);
    expect(editor.settings?.catalogIntervalMs, 1000);
    expect(editor.saving, isFalse);
  });

  test('other users never load the settings', () async {
    final editor = ResourceSettingsEditor(
      FakeRepository(),
      await openStore(viewerPreferences),
    );
    addTearDown(editor.dispose);

    await editor.load();
    expect(editor.allowed, isFalse);
    expect(editor.settings, isNull);
  });

  test('a failed save keeps the old settings and reports the error', () async {
    final editor = ResourceSettingsEditor(
      _FailingRepository(),
      await openStore(),
    );
    addTearDown(editor.dispose);
    await editor.load();

    await expectLater(
      editor.save(editor.settings!.copyWith(downloadConcurrency: 5)),
      throwsA(isA<AppFailure>()),
    );
    expect(editor.settings?.downloadConcurrency, 2);
    expect(editor.saving, isFalse);
  });
}
