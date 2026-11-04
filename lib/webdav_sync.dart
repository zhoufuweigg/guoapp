import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_build.dart';
import 'local_store.dart';

/// WebDAV 备份配置。凭据保存在本机 SharedPreferences，不会写入备份文件，
/// 也不会通过局域网同步外发。
class WebDavConfig {
  const WebDavConfig({
    this.uri = '',
    this.username = '',
    this.password = '',
    this.directory = defaultDirectory,
  });

  final String uri;
  final String username;
  final String password;
  final String directory;

  static const defaultDirectory = 'duanju';
  static const keyUri = 'webdavUri';
  static const keyUsername = 'webdavUsername';
  static const keyPassword = 'webdavPassword';
  static const keyDirectory = 'webdavDirectory';

  static Future<WebDavConfig> load(SharedPreferences preferences) async =>
      WebDavConfig(
        uri: preferences.getString(keyUri) ?? '',
        username: preferences.getString(keyUsername) ?? '',
        password: preferences.getString(keyPassword) ?? '',
        directory:
            preferences.getString(keyDirectory) ?? defaultDirectory,
      );

  Future<void> save(SharedPreferences preferences) async {
    await preferences.setString(keyUri, uri.trim());
    await preferences.setString(keyUsername, username.trim());
    await preferences.setString(keyPassword, password);
    await preferences.setString(keyDirectory, directory.trim());
  }

  /// 目录为空时回退到默认目录，避免把备份写到服务器根目录。
  String get effectiveDirectory =>
      directory.trim().isEmpty ? defaultDirectory : directory.trim();

  bool get isConfigured => uri.trim().isNotEmpty;

  WebDavConfig copyWith({
    String? uri,
    String? username,
    String? password,
    String? directory,
  }) => WebDavConfig(
    uri: uri ?? this.uri,
    username: username ?? this.username,
    password: password ?? this.password,
    directory: directory ?? this.directory,
  );

  Map<String, String> toJson() => {
    keyUri: uri,
    keyUsername: username,
    keyDirectory: directory,
  };
}

/// WebDAV 操作失败，消息面向终端用户。
class WebDavException implements Exception {
  const WebDavException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 极简 WebDAV 客户端：MKCOL 建目录、PUT 上传、GET 下载、DELETE 删除、
/// HEAD 探测。仅覆盖备份同步所需动词，避免引入额外依赖。
class WebDavClient {
  WebDavClient(this.config);

  final WebDavConfig config;

  static const _connectTimeout = Duration(seconds: 15);
  static const _ioTimeout = Duration(seconds: 90);

  Uri get _baseUri {
    var text = config.uri.trim();
    if (text.isEmpty) {
      throw const WebDavException('请先填写 WebDAV 地址');
    }
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      text = 'https://$text';
    }
    final parsed = Uri.parse(text).removeFragment();
    if (!parsed.hasAuthority || parsed.host.isEmpty) {
      throw const WebDavException('WebDAV 地址无效');
    }
    return parsed;
  }

  String get _username {
    if (config.username.isNotEmpty) return config.username;
    return _baseUri.userInfo.split(':').first;
  }

  String get _password {
    if (config.password.isNotEmpty) return config.password;
    final parts = _baseUri.userInfo.split(':');
    return parts.length > 1 ? parts.sublist(1).join(':') : '';
  }

  Uri _resolve(List<String> segments) {
    final base = _baseUri;
    final path = <String>[
      ...base.pathSegments.where((segment) => segment.isNotEmpty),
      ...segments.where((segment) => segment.isNotEmpty),
    ];
    return base.replace(
      pathSegments: path,
      // 清空 URL 内置凭据，统一走 Authorization 头，避免双重认证冲突。
      userInfo: '',
    );
  }

  Uri get directoryUri => _resolve(_directorySegments);
  Uri get backupFileUri => _resolve([..._directorySegments, backupFileName]);

  List<String> get _directorySegments {
    final raw = config.effectiveDirectory;
    return raw
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
  }

  /// 备份文件名按平台区分，多设备各保留一份，互不覆盖。
  String get backupFileName =>
      '$appSlug-backup-${Platform.operatingSystem}.json';

  Map<String, String> get _headers {
    final headers = <String, String>{
      HttpHeaders.acceptCharsetHeader: 'utf-8',
    };
    final user = _username;
    if (user.isNotEmpty || _password.isNotEmpty) {
      final credentials = base64.encode(utf8.encode('$user:$_password'));
      headers[HttpHeaders.authorizationHeader] = 'Basic $credentials';
    }
    return headers;
  }

  Future<HttpClientResponse> _send(
    String method,
    Uri url, {
    List<int>? body,
    Map<String, String>? headers,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = _connectTimeout
      ..idleTimeout = _connectTimeout;
    try {
      final request = await client
          .openUrl(method, url)
          .timeout(_connectTimeout);
      request.headers.contentLength = body?.length ?? 0;
      _headers.forEach(request.headers.set);
      headers?.forEach(request.headers.set);
      if (body != null) request.add(body);
      final response = await request.close().timeout(_ioTimeout);
      // 读干响应体，保证连接可被复用/正常关闭。
      await response.drain<void>();
      return response;
    } finally {
      client.close(force: true);
    }
  }

  static String _describe(Object error) {
    if (error is WebDavException) return error.message;
    if (error is TimeoutException) return '连接超时，请检查网络与地址';
    if (error is HandshakeException) return 'TLS 握手失败，请检查地址与证书';
    if (error is SocketException) {
      return '无法连接服务器（${error.osError?.message ?? error.message}）';
    }
    return error.toString();
  }

  /// 建立连接并逐级创建备份目录；配置错误时抛出中文可读异常。
  Future<void> connect() async {
    try {
      final base = _baseUri;
      // 先探测根路径：未配置认证时多数服务器返回 401，提前给出提示。
      final probe = await _send('HEAD', base);
      if (probe.statusCode == 401) {
        throw const WebDavException('WebDAV 认证失败，请检查账号密码');
      }
      final segments = _directorySegments;
      var current = <String>[];
      for (final segment in segments) {
        current = [...current, segment];
        final response = await _send('MKCOL', _resolve(current));
        if (response.statusCode >= 400 &&
            response.statusCode != 405 && // 目录已存在
            response.statusCode != 301 &&
            response.statusCode != 302) {
          throw WebDavException(
            '创建目录失败（$segment，状态码 ${response.statusCode}）',
          );
        }
      }
    } on WebDavException {
      rethrow;
    } catch (error) {
      throw WebDavException(_describe(error));
    }
  }

  /// 上传备份：先删除旧文件再写入，避免部分服务器覆盖语义差异。
  Future<void> write(String name, List<int> bytes) async {
    try {
      final target = _resolve([..._directorySegments, name]);
      try {
        final removed = await _send('DELETE', target);
        if (removed.statusCode >= 400 && removed.statusCode != 404) {
          // 删除失败不致命，继续尝试覆盖写。
        }
      } catch (_) {}
      final response = await _send('PUT', target, body: bytes);
      if (response.statusCode >= 300) {
        throw WebDavException('上传失败（状态码 ${response.statusCode}）');
      }
    } on WebDavException {
      rethrow;
    } catch (error) {
      throw WebDavException(_describe(error));
    }
  }

  Future<List<int>> read(String name) async {
    try {
      final target = _resolve([..._directorySegments, name]);
      final client = HttpClient()..connectionTimeout = _connectTimeout;
      try {
        final request = await client
            .openUrl('GET', target)
            .timeout(_connectTimeout);
        _headers.forEach(request.headers.set);
        final response = await request.close().timeout(_ioTimeout);
        if (response.statusCode == 404) {
          throw const WebDavException('远端没有找到备份文件');
        }
        if (response.statusCode >= 300) {
          throw WebDavException('下载失败（状态码 ${response.statusCode}）');
        }
        return await response.fold<List<int>>(
          <int>[],
          (bytes, chunk) => bytes..addAll(chunk),
        );
      } finally {
        client.close(force: true);
      }
    } on WebDavException {
      rethrow;
    } catch (error) {
      throw WebDavException(_describe(error));
    }
  }

  /// 远端备份的修改时间；不存在返回 null。
  Future<DateTime?> backupModifiedAt() async {
    try {
      final response = await _send('HEAD', backupFileUri);
      if (response.statusCode == 404) return null;
      if (response.statusCode == 401) {
        throw const WebDavException('WebDAV 认证失败，请检查账号密码');
      }
      if (response.statusCode >= 300) return null;
      final raw = response.headers.value(HttpHeaders.lastModifiedHeader);
      if (raw == null) return null;
      return HttpDate.parse(raw);
    } on WebDavException {
      rethrow;
    } catch (_) {
      return null;
    }
  }
}

/// WebDAV 同步服务：完全复用本地导出/恢复实现，只负责搬运备份文件。
class WebDavSync {
  const WebDavSync._();

  static const lastBackupAtKey = 'webdavLastBackupAt';

  /// 导出本地备份并上传。payload 与「导出配置备份」完全一致。
  static Future<void> backup({
    required SharedPreferences preferences,
    required LocalStore store,
  }) async {
    final config = await WebDavConfig.load(preferences);
    if (!config.isConfigured) {
      throw const WebDavException('请先填写并保存 WebDAV 配置');
    }
    final content = await store.exportBackup();
    final client = WebDavClient(config);
    await client.connect();
    await client.write(client.backupFileName, utf8.encode(content));
    await preferences.setString(
      lastBackupAtKey,
      DateTime.now().toIso8601String(),
    );
  }

  /// 下载远端备份内容，由调用方走既有校验与恢复流程。
  static Future<String> fetchBackup(SharedPreferences preferences) async {
    final config = await WebDavConfig.load(preferences);
    if (!config.isConfigured) {
      throw const WebDavException('请先填写并保存 WebDAV 配置');
    }
    final client = WebDavClient(config);
    await client.connect();
    final bytes = await client.read(client.backupFileName);
    final content = utf8.decode(bytes);
    if (content.length > 8 * 1024 * 1024) {
      throw const WebDavException('远端备份文件过大');
    }
    return content;
  }

  /// 探测配置是否可用，返回错误信息；成功返回 null。
  static Future<String?> testConnection(WebDavConfig config) async {
    try {
      await WebDavClient(config).connect();
      return null;
    } on WebDavException catch (error) {
      return error.message;
    } catch (error) {
      return error.toString();
    }
  }

  static Future<DateTime?> lastBackupAt(SharedPreferences preferences) async {
    final raw = preferences.getString(lastBackupAtKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }
}
