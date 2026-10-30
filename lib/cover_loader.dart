import 'dart:async';

import 'core_bridge.dart';
import 'models.dart';

class CoverRequest {
  CoverRequest._(this._start);
  final Future<String> Function() _start;
  final _result = Completer<String>();
  Timer? _delay;
  bool _cancelled = false;

  Future<String> get file => _result.future;

  void cancel() {
    if (_cancelled || _result.isCompleted) return;
    _cancelled = true;
    _delay?.cancel();
    CoverLoader._waiting.remove(this);
  }

  void _run() {
    CoverLoader._running++;
    _start()
        .then(_result.complete, onError: _result.completeError)
        .whenComplete(() {
          CoverLoader._running--;
          CoverLoader._drain();
        });
  }
}

abstract final class CoverLoader {
  static const _limit = 6;
  static const _delay = Duration(milliseconds: 150);
  static final _waiting = <CoverRequest>[];
  static var _running = 0;

  static Future<String>? cached(AppRepository repository, Drama drama) =>
      repository.coverCached(drama) ? repository.cover(drama) : null;

  static CoverRequest request(AppRepository repository, Drama drama) {
    final request = CoverRequest._(() => repository.cover(drama));
    request._delay = Timer(_delay, () {
      if (request._cancelled) return;
      _waiting.add(request);
      _drain();
    });
    return request;
  }

  static void _drain() {
    while (_running < _limit && _waiting.isNotEmpty) {
      _waiting.removeLast()._run();
    }
  }
}
