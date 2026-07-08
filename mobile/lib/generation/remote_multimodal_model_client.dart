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
    this.includeSourceVideo = false,
  });

  final Uri endpoint;
  final Duration timeout;
  final bool includeSourceVideo;

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
      final selectedFrames = _selectFramesForModel(frames);
      final request = await client.postUrl(endpoint).timeout(timeout);
      request.headers.contentType = ContentType.json;
      final videoBytes = includeSourceVideo
          ? await File(video.path).readAsBytes().timeout(timeout)
          : null;
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
          if (videoBytes != null)
            'sourceVideo': {
              'name': video.name,
              'type': video.mimeType ?? 'video/mp4',
              'data':
                  'data:${video.mimeType ?? 'video/mp4'};base64,${base64Encode(videoBytes)}',
            },
          'frameSelection': {
            'originalFrameCount': frames.length,
            'sentFrameIndexes': [
              for (final frame in selectedFrames) frame.index,
            ],
            'strategy': 'touch-events-with-neighbor-context',
          },
          'frames': [
            for (final frame in selectedFrames)
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

  List<VideoFrame> _selectFramesForModel(List<VideoFrame> frames) {
    if (frames.length <= 8) {
      return frames;
    }

    final touchIndexes = frames
        .where((frame) => frame.touchTarget != null)
        .map((frame) => frame.index)
        .toSet();
    if (touchIndexes.isNotEmpty) {
      final selectedIndexes = <int>{};
      for (final index in touchIndexes) {
        selectedIndexes.add((index - 1).clamp(0, frames.length - 1).toInt());
        selectedIndexes.add(index.clamp(0, frames.length - 1).toInt());
        selectedIndexes.add((index + 1).clamp(0, frames.length - 1).toInt());
      }

      final selected = [
        for (final index in selectedIndexes.toList()..sort()) frames[index],
      ];
      if (selected.length <= 12) {
        return selected;
      }
      return [
        for (final index in _evenIndexes(selected.length, 12)) selected[index],
      ];
    }

    return [for (final index in _evenIndexes(frames.length, 8)) frames[index]];
  }

  List<int> _evenIndexes(int length, int count) {
    if (length <= count) {
      return [for (var index = 0; index < length; index += 1) index];
    }
    return [
      for (var index = 0; index < count; index += 1)
        ((length - 1) * index / (count - 1)).round(),
    ];
  }
}
