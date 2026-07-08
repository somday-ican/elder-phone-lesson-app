import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/generation/prompt_builder.dart';
import 'package:mobile/generation/remote_multimodal_model_client.dart';
import 'package:mobile/models/lesson.dart';
import 'package:mobile/models/video_frame.dart';

void main() {
  test(
    'remote multimodal client posts frames and parses lesson response',
    () async {
      late Map<String, Object?> receivedPayload;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        receivedPayload =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, Object?>;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'lesson': {
              'schemaVersion': lessonSchemaVersion,
              'id': 'lesson_remote',
              'title': '远程教程',
              'summary': '由多模态模型生成',
              'createdAt': DateTime.utc(2026, 7, 8).toIso8601String(),
              'source': {
                'type': 'video_frames',
                'frameCount': 1,
                'generator': 'remote_multimodal',
              },
              'steps': [
                {
                  'id': 'step_1',
                  'order': 1,
                  'title': '点击按钮',
                  'instruction': '轻点高亮位置。',
                  'action': {
                    'type': 'tap',
                    'target': {'x': 0.4, 'y': 0.6},
                  },
                  'frameIndex': 0,
                },
              ],
            },
          }),
        );
        await request.response.close();
      });

      final frames = [
        VideoFrame(
          index: 0,
          time: Duration.zero,
          bytes: Uint8List.fromList([1, 2, 3]),
          touchTarget: const RelativeTarget(x: 0.4, y: 0.6),
        ),
      ];
      final videoFile = File(
        '${Directory.systemTemp.path}/remote_client_demo.mp4',
      );
      await videoFile.writeAsBytes([9, 8, 7, 6]);
      addTearDown(() {
        if (videoFile.existsSync()) {
          videoFile.deleteSync();
        }
      });
      final video = SelectedVideo(
        path: videoFile.path,
        name: 'demo.mp4',
        mimeType: 'video/mp4',
        duration: const Duration(seconds: 2),
        aspectRatio: 9 / 16,
      );
      final prompt = const PromptBuilder().build(
        frames: frames,
        video: video,
        audience: 'elderly smartphone user',
        goal: '生成老人教程',
      );

      final lesson =
          await RemoteMultimodalModelClient(
            endpoint: Uri.parse('http://127.0.0.1:${server.port}/lessons'),
          ).generateLessonJson(
            frames: frames,
            video: video,
            audience: 'elderly smartphone user',
            goal: '生成老人教程',
            prompt: prompt,
          );

      expect(lesson.id, 'lesson_remote');
      expect(lesson.steps.single.action.target.x, 0.4);
      expect(receivedPayload['goal'], '生成老人教程');
      expect(receivedPayload['sourceVideo'], isA<Map<String, Object?>>());
      expect(receivedPayload['frames'], isA<List<Object?>>());
    },
  );
}
