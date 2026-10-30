import 'dart:async';

import 'package:duanju_app/drama_feed.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  final a = drama('a'), b = drama('b'), c = drama('c');

  DramaFeed feedOf(DramaFeed feed) {
    addTearDown(feed.dispose);
    return feed;
  }

  test('stale cache shows first, then the first page replaces it', () async {
    final first = Completer<CatalogPage>();
    final feed = feedOf(
      DramaFeed(
        cached: () async => CatalogPage([a], page: 7, hasMore: true),
        load: (page, force) => first.future,
      ),
    );
    final reload = feed.reload();
    await pumpEventQueue();
    expect(feed.items, [a]);
    expect(feed.loading, isTrue);

    first.complete(CatalogPage([b], hasMore: true));
    await reload;
    expect(feed.items, [b]);
    expect(feed.loading, isFalse);
  });

  test('fresh cache skips the network and continues its page', () async {
    final pages = <int>[];
    final feed = feedOf(
      DramaFeed(
        cached: () async =>
            CatalogPage([a], page: 7, hasMore: true, fresh: true),
        load: (page, force) async {
          pages.add(page);
          return CatalogPage([b], page: page);
        },
      ),
    );
    await feed.reload();
    expect(pages, isEmpty);
    await feed.loadMore();
    expect(pages, [8]);
    expect(feed.items, [a, b]);
    expect(feed.hasMore, isFalse);
  });

  test('forced reloads skip the cache', () async {
    final forced = <bool>[];
    final feed = feedOf(
      DramaFeed(
        cached: () async => CatalogPage([a], fresh: true),
        load: (page, force) async {
          forced.add(force);
          return CatalogPage([b]);
        },
      ),
    );
    await feed.reload(force: true);
    expect(forced, [true]);
    expect(feed.items, [b]);
  });

  test('pages merge without repeats and a warning retries its page', () async {
    final pages = <int>[];
    final feed = feedOf(
      DramaFeed(
        load: (page, force) async {
          pages.add(page);
          return page == 1
              ? CatalogPage([a, b], hasMore: true)
              : CatalogPage([b, c], page: 2, warning: '部分失败');
        },
      ),
    );
    await feed.reload();
    await feed.loadMore();
    expect(feed.items, [a, b, c]);
    expect(feed.error, '部分失败');
    expect(feed.hasMore, isTrue);
    expect(feed.canLoadMore, isFalse);

    await feed.loadMore();
    expect(pages, [1, 2, 2]);
  });

  test('cumulative feeds replace their items with each answer', () async {
    final feed = feedOf(
      DramaFeed(
        cumulative: true,
        load: (page, force) async =>
            CatalogPage(page == 1 ? [a] : [a, b], hasMore: page == 1),
      ),
    );
    await feed.reload();
    await feed.loadMore();
    expect(feed.items, [a, b]);
  });

  test('an older answer never overwrites a newer reload', () async {
    final answers = <Completer<CatalogPage>>[];
    final feed = feedOf(
      DramaFeed(
        load: (page, force) {
          answers.add(Completer());
          return answers.last.future;
        },
      ),
    );
    final older = feed.reload();
    final newer = feed.reload();
    answers[1].complete(CatalogPage([b]));
    await newer;
    answers[0].complete(CatalogPage([a]));
    await older;
    expect(feed.items, [b]);
  });

  test('a failure is shown until the next reload succeeds', () async {
    var fail = true;
    final feed = feedOf(
      DramaFeed(
        load: (page, force) async =>
            fail ? throw StateError('网络错误') : CatalogPage([a]),
      ),
    );
    await feed.reload();
    expect(feed.items, isEmpty);
    expect(feed.error, contains('网络错误'));

    fail = false;
    await feed.reload(force: true);
    expect(feed.error, isEmpty);
    expect(feed.items, [a]);
  });
}
