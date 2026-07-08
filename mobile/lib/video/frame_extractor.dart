import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../models/video_frame.dart';

class FrameExtractor {
  const FrameExtractor({
    this.maxFrames = 16,
    this.maxWidth = 540,
    this.quality = 68,
  });

  final int maxFrames;
  final int maxWidth;
  final int quality;
  static const _channel = MethodChannel('video_to_lesson/frame_extractor');

  Future<List<VideoFrame>> extract(SelectedVideo video) async {
    final durationMs = video.duration.inMilliseconds;
    final safeDurationMs = durationMs > 0 ? durationMs : 1000;
    final count = math.min(
      maxFrames,
      math.max(4, (safeDurationMs / 450).ceil()),
    );
    final frames = <VideoFrame>[];

    for (var index = 0; index < count; index += 1) {
      final lastMs = math.max(safeDurationMs - 50, 0);
      final timeMs = count == 1 ? 0 : (lastMs * index / (count - 1)).round();
      final bytes = await _channel.invokeMethod<Uint8List>('extractFrame', {
        'path': video.path,
        'timeMs': timeMs,
        'maxWidth': maxWidth,
        'quality': quality,
      });
      if (bytes != null && bytes.isNotEmpty) {
        frames.add(
          VideoFrame(
            index: frames.length,
            time: Duration(milliseconds: timeMs),
            bytes: Uint8List.fromList(bytes),
          ),
        );
      }
    }

    return frames;
  }
}
