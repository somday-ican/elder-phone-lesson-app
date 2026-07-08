import 'dart:typed_data';

import 'lesson.dart';

class VideoFrame {
  const VideoFrame({
    required this.index,
    required this.time,
    required this.bytes,
    this.touchTarget,
  });

  final int index;
  final Duration time;
  final Uint8List bytes;
  final RelativeTarget? touchTarget;

  VideoFrame copyWith({
    RelativeTarget? touchTarget,
    bool clearTouchTarget = false,
  }) {
    return VideoFrame(
      index: index,
      time: time,
      bytes: bytes,
      touchTarget: clearTouchTarget ? null : touchTarget ?? this.touchTarget,
    );
  }
}

class SelectedVideo {
  const SelectedVideo({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.duration,
    required this.aspectRatio,
  });

  final String path;
  final String name;
  final String? mimeType;
  final Duration duration;
  final double aspectRatio;
}
