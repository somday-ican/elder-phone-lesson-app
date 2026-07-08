import '../models/video_frame.dart';

class LessonPrompt {
  const LessonPrompt({required this.system, required this.user});

  final String system;
  final Map<String, Object?> user;
}

class PromptBuilder {
  const PromptBuilder();

  LessonPrompt build({
    required List<VideoFrame> frames,
    required SelectedVideo video,
    required String audience,
    required String goal,
  }) {
    return LessonPrompt(
      system: [
        'You generate step-by-step smartphone operation lessons for elderly users.',
        'Return strict JSON matching the shared lesson schema.',
        'Use relative coordinates from 0 to 1 for every action target.',
      ].join(' '),
      user: {
        'goal': goal,
        'audience': audience,
        'videoMeta': {
          'name': video.name,
          'type': video.mimeType,
          'duration': video.duration.inMilliseconds / 1000,
          'aspectRatio': video.aspectRatio,
        },
        'frameCount': frames.length,
        'frameFormat': 'local thumbnail bytes',
      },
    );
  }
}
