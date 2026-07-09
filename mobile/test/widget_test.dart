import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';

void main() {
  testWidgets('shows the home page with card-based UI', (
    tester,
  ) async {
    await tester.pumpWidget(const VideoToLessonApp());

    expect(find.text('学手机'), findsOneWidget);
    expect(find.text('告诉我你想学什么'), findsOneWidget);
  });
}
