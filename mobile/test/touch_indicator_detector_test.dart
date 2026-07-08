import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:mobile/models/video_frame.dart';
import 'package:mobile/vision/touch_indicator_detector.dart';

void main() {
  test('detects a bright touch indicator dot in a frame', () async {
    final frameImage = image.Image(width: 200, height: 400);
    image.fill(frameImage, color: image.ColorRgb8(32, 42, 52));
    image.fillCircle(
      frameImage,
      x: 140,
      y: 280,
      radius: 14,
      color: image.ColorRgb8(245, 245, 245),
    );
    final bytes = Uint8List.fromList(image.encodeJpg(frameImage, quality: 92));

    final results = await const LocalTouchIndicatorDetector(
      minConfidence: 0.2,
    ).detect([VideoFrame(index: 0, time: Duration.zero, bytes: bytes)]);

    expect(results, hasLength(1));
    expect(results.single.target.x, closeTo(0.7, 0.08));
    expect(results.single.target.y, closeTo(0.7, 0.08));
  });

  test(
    'temporal detector ignores static circles and detects new tap dot',
    () async {
      final first = image.Image(width: 220, height: 420);
      final second = image.Image(width: 220, height: 420);
      image.fill(first, color: image.ColorRgb8(42, 42, 42));
      image.fill(second, color: image.ColorRgb8(42, 42, 42));

      for (final point in const [
        (x: 50, y: 90),
        (x: 145, y: 90),
        (x: 50, y: 180),
        (x: 145, y: 180),
      ]) {
        image.drawCircle(
          first,
          x: point.x,
          y: point.y,
          radius: 9,
          color: image.ColorRgb8(235, 235, 235),
        );
        image.drawCircle(
          second,
          x: point.x,
          y: point.y,
          radius: 9,
          color: image.ColorRgb8(235, 235, 235),
        );
      }

      image.fillCircle(
        second,
        x: 172,
        y: 318,
        radius: 13,
        color: image.ColorRgb8(245, 245, 245),
      );

      final results =
          await const IsolateTouchIndicatorDetector(
            minConfidence: 0.18,
          ).detect([
            VideoFrame(
              index: 0,
              time: Duration.zero,
              bytes: Uint8List.fromList(image.encodeJpg(first, quality: 92)),
            ),
            VideoFrame(
              index: 1,
              time: const Duration(milliseconds: 450),
              bytes: Uint8List.fromList(image.encodeJpg(second, quality: 92)),
            ),
          ]);

      expect(results, hasLength(1));
      expect(results.single.frameIndex, 1);
      expect(results.single.target.x, closeTo(172 / 220, 0.08));
      expect(results.single.target.y, closeTo(318 / 420, 0.08));
    },
  );
}
