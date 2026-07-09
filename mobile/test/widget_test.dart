import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';

void main() {
  testWidgets('shows home page with voice-first design', (tester) async {
    await tester.pumpWidget(const VideoToLessonApp());

    expect(find.text('阿姨，早上好 👋'), findsOneWidget);
    expect(find.text('点击说话'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
  });
}
