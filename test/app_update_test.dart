import 'package:duanju_app/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('拆分架构 APK 的版本号还原为构建号', () {
    expect(baseBuildNumber('101'), 101);
    expect(baseBuildNumber('2101'), 101);
    expect(baseBuildNumber('4101'), 101);
    expect(baseBuildNumber(''), 0);
  });
}
