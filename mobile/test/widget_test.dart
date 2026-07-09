import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';

void main() {
  testWidgets('shows the voice-first home page', (tester) async {
    await tester.pumpWidget(const VideoToLessonApp());

    expect(find.text('阿姨，早上好'), findsOneWidget);
    expect(find.textContaining('想学什么'), findsOneWidget);
    expect(find.text('点击说话'), findsOneWidget);
  });
}
