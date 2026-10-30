import 'dart:async';

import 'package:media_kit/media_kit.dart';

class FakePlayer implements Player {
  @override
  PlayerState state = const PlayerState();
  final opened = <Media>[];
  final rates = <double>[];
  final seeks = <Duration>[];
  var stops = 0;
  var disposed = false;
  final _playing = StreamController<bool>.broadcast(sync: true);
  final _completed = StreamController<bool>.broadcast(sync: true);
  final _position = StreamController<Duration>.broadcast(sync: true);
  final _duration = StreamController<Duration>.broadcast(sync: true);
  final _videoParams = StreamController<VideoParams>.broadcast(sync: true);
  final _error = StreamController<String>.broadcast(sync: true);
  final _buffering = StreamController<bool>.broadcast(sync: true);

  @override
  PlatformPlayer? platform;

  @override
  late final PlayerStream stream = PlayerStream(
    const Stream.empty(),
    _playing.stream,
    _completed.stream,
    _position.stream,
    _duration.stream,
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    _buffering.stream,
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    _videoParams.stream,
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    _error.stream,
  );

  void progress(Duration position, {Duration? duration}) {
    state = state.copyWith(
      position: position,
      duration: duration ?? state.duration,
    );
    if (duration != null) _duration.add(duration);
    _position.add(position);
  }

  void finish() {
    state = state.copyWith(
      position: state.duration,
      completed: true,
      playing: false,
    );
    _completed.add(true);
  }

  void fail(String message) => _error.add(message);

  void buffer(bool buffering) {
    state = state.copyWith(buffering: buffering);
    _buffering.add(buffering);
  }

  void resize(int width, int height) =>
      _videoParams.add(VideoParams(w: width, h: height));

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opened.add(playable as Media);
    state = state.copyWith(
      playing: play,
      completed: false,
      position: playable.start ?? Duration.zero,
    );
    _playing.add(play);
  }

  @override
  Future<void> stop() async {
    stops++;
    state = state.copyWith(playing: false, position: Duration.zero);
  }

  @override
  Future<void> play() async {
    state = state.copyWith(playing: true);
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    state = state.copyWith(playing: false);
    _playing.add(false);
  }

  @override
  Future<void> playOrPause() => state.playing ? pause() : play();

  @override
  Future<void> seek(Duration duration) async {
    seeks.add(duration);
    state = state.copyWith(position: duration);
  }

  @override
  Future<void> setRate(double rate) async {
    rates.add(rate);
    state = state.copyWith(rate: rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    state = state.copyWith(volume: volume);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
