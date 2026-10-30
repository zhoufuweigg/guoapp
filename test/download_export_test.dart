import 'package:duanju_app/download_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('export names pad episode numbers to the episode count', () {
    expect(exportFileName(1, 0), '第01集.mp4');
    expect(exportFileName(7, 80), '第07集.mp4');
    expect(exportFileName(7, 120), '第007集.mp4');
    expect(exportFileName(105, 90), '第105集.mp4');
  });
}
