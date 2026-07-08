import '../models/lesson.dart';
import '../models/video_frame.dart';
import 'prompt_builder.dart';

abstract class ModelClient {
  bool get supportsDirectVideo => false;

  Future<Lesson> generateLessonJson({
    required List<VideoFrame> frames,
    required SelectedVideo video,
    required String audience,
    required String goal,
    required LessonPrompt prompt,
  });
}
