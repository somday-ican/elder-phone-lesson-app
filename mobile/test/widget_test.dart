import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';

void main() {
  testWidgets('shows the screenshot to lesson workflow entry points', (
    tester,
  ) async {
    await tester.pumpWidget(const VideoToLessonApp());

    expect(find.text('长辈学手机'), findsOneWidget);
    expect(find.text('选择截图'), findsOneWidget);
    expect(find.text('生成教程'), findsOneWidget);
    expect(find.text('教程会在这里展示'), findsOneWidget);
  });
}
