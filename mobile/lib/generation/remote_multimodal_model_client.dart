import 'dart:convert';
import 'dart:io';

import '../models/lesson.dart';
import '../models/video_frame.dart';
import 'model_client.dart';
import 'prompt_builder.dart';

class RemoteMultimodalModelClient implements ModelClient {
  const RemoteMultimodalModelClient({
    required this.endpoint,
    this.timeout = const Duration(seconds: 120),
  });

  final Uri endpoint;
  final Duration timeout;

  @override
  bool get supportsDirectVideo => true;

  @override
  Future<Lesson> generateLessonJson({
    required List<VideoFrame> frames,
    required SelectedVideo video,
    required String audience,
    required String goal,
    required LessonPrompt prompt,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final request = await client.postUrl(endpoint).timeout(timeout);
      request.headers.contentType = ContentType.json;
      final videoBytes = await File(video.path).readAsBytes().timeout(timeout);
      request.write(
        jsonEncode({
          'goal': goal,
          'audience': audience,
          'prompt': {'system': prompt.system, 'user': prompt.user},
          'videoMeta': {
            'name': video.name,
            'type': video.mimeType,
            'duration': video.duration.inMilliseconds / 1000,
            'aspectRatio': video.aspectRatio,
          },
          'sourceVideo': {
            'name': video.name,
            'type': video.mimeType ?? 'video/mp4',
            'data':
                'data:${video.mimeType ?? 'video/mp4'};base64,${base64Encode(videoBytes)}',
          },
          'frames': [
            for (final frame in frames)
              {
                'index': frame.index,
                'timeMs': frame.time.inMilliseconds,
                'image': 'data:image/jpeg;base64,${base64Encode(frame.bytes)}',
                if (frame.touchTarget != null)
                  'touchCandidate': frame.touchTarget!.toJson(),
              },
          ],
          'schema': {
            'schemaVersion': lessonSchemaVersion,
            'coordinateSystem': 'relative-0-1',
            'requiredStepFields': [
              'title',
              'instruction',
              'action.type',
              'frameIndex',
              'action.target.x',
              'action.target.y',
            ],
          },
        }),
      );

      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Lesson API returned ${response.statusCode}: $body',
          uri: endpoint,
        );
      }

      final payload = jsonDecode(body) as Map<String, Object?>;
      final lessonJson =
          (payload['lesson'] as Map?)?.cast<String, Object?>() ?? payload;
      return Lesson.fromJson(lessonJson);
    } finally {
      client.close(force: true);
    }
  }
}
