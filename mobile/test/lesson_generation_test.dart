import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/generation/lesson_validator.dart';
import 'package:mobile/generation/mock_lesson_generator.dart';
import 'package:mobile/generation/prompt_builder.dart';
import 'package:mobile/models/lesson.dart';
import 'package:mobile/models/video_frame.dart';

void main() {
  test('mock generator returns a valid elderly lesson', () async {
    final frames = [
      for (var index = 0; index < 4; index += 1)
        VideoFrame(
          index: index,
          time: Duration(seconds: index * 2),
          bytes: Uint8List.fromList([index]),
        ),
    ];
    const video = SelectedVideo(
      path: '/tmp/demo.mp4',
      name: 'demo.mp4',
      mimeType: 'video/mp4',
      duration: Duration(seconds: 8),
      aspectRatio: 9 / 16,
    );
    const goal = '教老人完成一次手机操作';

    final prompt = const PromptBuilder().build(
      frames: frames,
      video: video,
      audience: 'elderly smartphone user',
      goal: goal,
    );
    final lesson = await const MockLessonGenerator().generateLessonJson(
      frames: frames,
      video: video,
      audience: 'elderly smartphone user',
      goal: goal,
      prompt: prompt,
    );

    final validation = const LessonValidator().validate(lesson);

    expect(validation.ok, isTrue);
    expect(lesson.steps, hasLength(4));
    expect(lesson.steps.first.action.target.x, inInclusiveRange(0, 1));
    expect(lesson.steps.first.frameIndex, 0);
  });

  test('mock generator uses manually marked touch targets', () async {
    final frames = [
      VideoFrame(
        index: 0,
        time: Duration.zero,
        bytes: Uint8List.fromList([0]),
        touchTarget: const RelativeTarget(
          x: 0.25,
          y: 0.75,
          width: 0.18,
          height: 0.09,
          label: '真实点击位置',
        ),
      ),
      VideoFrame(
        index: 1,
        time: const Duration(seconds: 2),
        bytes: Uint8List.fromList([1]),
      ),
    ];
    const video = SelectedVideo(
      path: '/tmp/demo.mp4',
      name: 'demo.mp4',
      mimeType: 'video/mp4',
      duration: Duration(seconds: 4),
      aspectRatio: 9 / 16,
    );
    final prompt = const PromptBuilder().build(
      frames: frames,
      video: video,
      audience: 'elderly smartphone user',
      goal: '教老人完成一次手机操作',
    );

    final lesson = await const MockLessonGenerator().generateLessonJson(
      frames: frames,
      video: video,
      audience: 'elderly smartphone user',
      goal: '教老人完成一次手机操作',
      prompt: prompt,
    );

    expect(lesson.steps, hasLength(1));
    expect(lesson.steps.single.frameIndex, 0);
    expect(lesson.steps.single.action.target.x, 0.25);
    expect(lesson.steps.single.action.target.y, 0.75);
  });
}
