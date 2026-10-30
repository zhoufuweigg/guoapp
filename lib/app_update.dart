import 'package:package_info_plus/package_info_plus.dart';

class AppUpdate {
  const AppUpdate({required this.version, required this.url});
  final String version;
  final String url;
}

int baseBuildNumber(String buildNumber) =>
    (int.tryParse(buildNumber) ?? 0) % 1000;

Future<String> currentAppVersion() async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version}+${baseBuildNumber(info.buildNumber)}';
}
