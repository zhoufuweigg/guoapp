import 'dart:io';

import 'package:flutter/material.dart';

import '../../core_bridge.dart';
import '../../cover_loader.dart';
import '../../models.dart';
import '../app_scope.dart';

const vipGold = Color(0xFFF6C86B);
const onVipGold = Color(0xFF40300D);

class VipBadge extends StatelessWidget {
  const VipBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: vipGold,
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Text(
      'VIP',
      style: TextStyle(
        color: onVipGold,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        height: 1.2,
      ),
    ),
  );
}

class DramaCover extends StatelessWidget {
  const DramaCover({
    super.key,
    required this.drama,
    this.radius = 12,
    this.details = true,
    this.rank,
  });
  final Drama drama;
  final double radius;
  final bool details;
  final int? rank;
  static const imagesDisabled = bool.fromEnvironment('DISABLE_REMOTE_IMAGES');

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.movie_creation_outlined,
          size: 36,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          placeholder,
          if (!imagesDisabled && drama.id.isNotEmpty)
            CoverImage(
              key: ValueKey('${drama.id}\u0000${drama.cover}'),
              drama: drama,
              repository: AppScope.of(context).repository,
              placeholder: placeholder,
            ),
          if (details)
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xC7000000)],
                  ),
                ),
              ),
            ),
          if (details && drama.episodes > 0)
            Positioned(
              left: 9,
              bottom: 9,
              child: Text(
                '共 ${drama.episodes} 集',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          if (details && drama.vip)
            Positioned(
              left: rank == null ? 8 : null,
              right: rank == null ? null : 8,
              top: 8,
              child: const VipBadge(),
            ),
          if (rank case final rank?)
            Positioned(left: 0, top: 0, child: RankBadge(rank: rank)),
        ],
      ),
    );
  }
}

class RankBadge extends StatelessWidget {
  const RankBadge({super.key, required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = rank <= 3;
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: !top
            ? const Color(0x8C000000)
            : theme.brightness == Brightness.dark
            ? theme.colorScheme.inversePrimary
            : theme.colorScheme.primary,
        borderRadius: const BorderRadius.only(bottomRight: Radius.circular(10)),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          color: Colors.white,
          fontSize: top ? 15 : 13,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class CoverImage extends StatefulWidget {
  const CoverImage({
    super.key,
    required this.drama,
    required this.repository,
    required this.placeholder,
    this.retryable = true,
  });
  final Drama drama;
  final AppRepository repository;
  final Widget placeholder;
  final bool retryable;

  @override
  State<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<CoverImage> {
  static const _decodeWidth = 440;
  CoverRequest? _request;
  Future<String>? _file;
  int _revision = 0;
  bool _failed = false;
  bool _retryOnFailure = false;
  bool _retryQueued = false;
  String? _failedPath;

  @override
  void initState() {
    super.initState();
    _revision = widget.repository.catalogUpdates.coverRevision(widget.drama.id);
    widget.repository.catalogUpdates.addListener(_metadataChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant CoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      oldWidget.repository.catalogUpdates.removeListener(_metadataChanged);
      widget.repository.catalogUpdates.addListener(_metadataChanged);
    }
    if (oldWidget.repository != widget.repository ||
        oldWidget.drama.source != widget.drama.source) {
      _failed = _retryOnFailure = false;
      _failedPath = null;
      _revision = widget.repository.catalogUpdates.coverRevision(
        widget.drama.id,
      );
      _load();
    }
  }

  @override
  void dispose() {
    _request?.cancel();
    widget.repository.catalogUpdates.removeListener(_metadataChanged);
    super.dispose();
  }

  void _load() {
    _request?.cancel();
    _request = null;
    _file = CoverLoader.cached(widget.repository, widget.drama);
    if (_file != null) return;
    final request = _request = CoverLoader.request(
      widget.repository,
      widget.drama,
    );
    _file = request.file;
  }

  void _metadataChanged() {
    final revision = widget.repository.catalogUpdates.coverRevision(
      widget.drama.id,
    );
    if (revision == _revision) return;
    _revision = revision;
    _retryOnFailure = true;
    if (_failed) _queueRetry();
  }

  void _queueRetry() {
    if (_retryQueued || !_retryOnFailure) return;
    _retryQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retryQueued = false;
      if (!mounted || !_retryOnFailure) return;
      _retryOnFailure = false;
      _retry(_failedPath);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _retry(String? path) async {
    if (path != null) {
      await ResizeImage.resizeIfNeeded(
        _decodeWidth,
        null,
        FileImage(File(path)),
      ).evict();
    }
    if (!mounted) return;
    _request?.cancel();
    setState(() {
      _request = null;
      _failed = _retryOnFailure = false;
      _failedPath = null;
      _file = widget.repository.cover(
        widget.repository.catalogUpdates.current(widget.drama),
        force: true,
      );
    });
  }

  Widget _failure(String? path) {
    _failed = true;
    _failedPath = path;
    if (_retryOnFailure) _queueRetry();
    if (!widget.retryable) return widget.placeholder;
    return Center(
      child: IconButton(
        tooltip: '重试海报',
        onPressed: () => _retry(path),
        icon: Icon(
          Icons.refresh_rounded,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _file,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return widget.placeholder;
      }
      if (snapshot.hasError || !snapshot.hasData) return _failure(null);
      return Image.file(
        File(snapshot.data!),
        fit: BoxFit.cover,
        cacheWidth: _decodeWidth,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => _failure(snapshot.data),
      );
    },
  );
}
