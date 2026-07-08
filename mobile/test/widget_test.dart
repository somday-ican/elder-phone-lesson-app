import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';

void main() {
  testWidgets('shows the video to lesson workflow entry points', (
    tester,
  ) async {
    await tester.pumpWidget(const VideoToLessonApp());

    expect(find.text('手机操作教程生成器'), findsOneWidget);
    expect(find.text('选择视频'), findsOneWidget);
    expect(find.text('抽取关键帧'), findsOneWidget);
    expect(find.text('生成教程 (0)'), findsOneWidget);
    expect(find.text('教程会在这里展示'), findsOneWidget);
  });
}
