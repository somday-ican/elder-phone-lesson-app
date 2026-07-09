import '../models/button_analysis.dart';
import '../models/lesson.dart';
import '../models/ui_description.dart';
import '../models/video_frame.dart';
import 'prompt_builder.dart';

class ChatGenerationResult {
  const ChatGenerationResult({
    required this.html,
    required this.title,
    required this.steps,
  });

  final String html;
  final String title;
  final List<({int stepIndex, String instruction, String elderTip})> steps;
}

abstract class ModelClient {
  bool get supportsDirectVideo => false;

  Future<Lesson> generateLessonJson({
    required List<VideoFrame> frames,
    required SelectedVideo video,
    required String audience,
    required String goal,
    required LessonPrompt prompt,
  });

  Future<ButtonAnalysis?> analyzeButton({
    required VideoFrame frame,
    required double markedX,
    required double markedY,
    required String goal,
  });

  Future<UIGenerationResult?> generateUI({
    required List<VideoFrame> frames,
    required List<({double x, double y})> markedPositions,
    required String goal,
  });

  Future<ChatGenerationResult> chatGenerate({
    required String goal,
    int stepCount = 5,
  });
}
