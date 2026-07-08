import 'dart:isolate';
import 'dart:math' as math;

import 'package:image/image.dart' as image;

import '../models/lesson.dart';
import '../models/video_frame.dart';

class TouchDetectionResult {
  const TouchDetectionResult({
    required this.frameIndex,
    required this.target,
    required this.confidence,
  });

  final int frameIndex;
  final RelativeTarget target;
  final double confidence;
}

abstract class TouchIndicatorDetector {
  Future<List<TouchDetectionResult>> detect(List<VideoFrame> frames);
}

class TemporalTouchIndicatorDetector implements TouchIndicatorDetector {
  const TemporalTouchIndicatorDetector({this.minConfidence = 0.2});

  final double minConfidence;

  @override
  Future<List<TouchDetectionResult>> detect(List<VideoFrame> frames) async {
    return detectSync(frames);
  }

  List<TouchDetectionResult> detectSync(List<VideoFrame> frames) {
    final decodedFrames = [
      for (final frame in frames)
        (frame: frame, bitmap: image.decodeImage(frame.bytes)),
    ].where((item) => item.bitmap != null).toList();

    if (decodedFrames.length < 2) {
      return const LocalTouchIndicatorDetector().detectSync(frames);
    }

    final results = <TouchDetectionResult>[];
    for (var index = 1; index < decodedFrames.length; index += 1) {
      final previous = decodedFrames[index - 1].bitmap!;
      final current = decodedFrames[index].bitmap!;
      if (previous.width != current.width ||
          previous.height != current.height) {
        continue;
      }

      final candidate = _findChangedTouchDot(
        previous: previous,
        current: current,
        frameIndex: decodedFrames[index].frame.index,
      );
      if (candidate != null && candidate.confidence >= minConfidence) {
        results.add(candidate);
      }
    }

    final deduped = _dedupeNearbyResults(results);
    if (deduped.isNotEmpty) {
      return deduped;
    }

    return const LocalTouchIndicatorDetector(
      minConfidence: 0.34,
    ).detectSync(frames);
  }

  TouchDetectionResult? _findChangedTouchDot({
    required image.Image previous,
    required image.Image current,
    required int frameIndex,
  }) {
    final width = current.width;
    final height = current.height;
    final sampleStep = math.max(1, (math.min(width, height) / 260).round());
    final topInset = (height * 0.055).round();
    final candidates = <_PixelCandidate>[];

    for (var y = topInset; y < height; y += sampleStep) {
      for (var x = 0; x < width; x += sampleStep) {
        final now = current.getPixel(x, y);
        final before = previous.getPixel(x, y);
        final nowBrightness = _brightness(now);
        final beforeBrightness = _brightness(before);
        final delta = _colorDelta(now, before);
        final saturation = _saturation(now);

        if (nowBrightness > 0.54 && saturation < 0.3 && delta > 0.13) {
          final contrast = _localContrast(current, x, y, sampleStep * 5);
          final score =
              (delta * 0.56) + (nowBrightness * 0.26) + (contrast * 0.18);
          candidates.add(_PixelCandidate(x: x, y: y, score: score.clamp(0, 1)));
        } else if (nowBrightness - beforeBrightness > 0.16 &&
            saturation < 0.36) {
          final score = ((nowBrightness - beforeBrightness) * 0.74) + 0.18;
          candidates.add(_PixelCandidate(x: x, y: y, score: score.clamp(0, 1)));
        }
      }
    }

    if (candidates.isEmpty) {
      return null;
    }

    final clusters = _clusterCandidates(
      candidates,
      sampleStep * 8,
      width,
      height,
    );
    if (clusters.isEmpty) {
      return null;
    }

    clusters.sort((a, b) => b.score.compareTo(a.score));
    final cluster = clusters.first;
    final diameter = cluster.diameter;
    final minDiameter = math.min(width, height) * 0.012;
    final maxDiameter = math.min(width, height) * 0.16;
    if (diameter < minDiameter || diameter > maxDiameter) {
      return null;
    }

    return TouchDetectionResult(
      frameIndex: frameIndex,
      target: RelativeTarget(
        x: (cluster.centerX / width).clamp(0, 1).toDouble(),
        y: (cluster.centerY / height).clamp(0, 1).toDouble(),
        width: (diameter * 1.9 / width).clamp(0.08, 0.22).toDouble(),
        height: (diameter * 1.9 / height).clamp(0.05, 0.14).toDouble(),
        label: '帧差分识别触摸点',
      ),
      confidence: cluster.score.clamp(0, 1).toDouble(),
    );
  }

  List<TouchDetectionResult> _dedupeNearbyResults(
    List<TouchDetectionResult> results,
  ) {
    final sorted = [...results]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <TouchDetectionResult>[];
    for (final result in sorted) {
      final duplicate = kept.any((other) {
        final dx = result.target.x - other.target.x;
        final dy = result.target.y - other.target.y;
        return math.sqrt(dx * dx + dy * dy) < 0.08;
      });
      if (!duplicate) {
        kept.add(result);
      }
    }
    kept.sort((a, b) => a.frameIndex.compareTo(b.frameIndex));
    return kept;
  }
}

class LocalTouchIndicatorDetector implements TouchIndicatorDetector {
  const LocalTouchIndicatorDetector({this.minConfidence = 0.28});

  final double minConfidence;

  @override
  Future<List<TouchDetectionResult>> detect(List<VideoFrame> frames) async {
    return detectSync(frames);
  }

  List<TouchDetectionResult> detectSync(List<VideoFrame> frames) {
    final results = <TouchDetectionResult>[];

    for (final frame in frames) {
      final decoded = image.decodeImage(frame.bytes);
      if (decoded == null) {
        continue;
      }
      final candidate = _findTouchDot(decoded, frame.index);
      if (candidate != null && candidate.confidence >= minConfidence) {
        results.add(candidate);
      }
    }

    return results;
  }

  TouchDetectionResult? _findTouchDot(image.Image frame, int frameIndex) {
    final width = frame.width;
    final height = frame.height;
    if (width < 20 || height < 20) {
      return null;
    }

    final sampleStep = math.max(1, (math.min(width, height) / 220).round());
    final candidates = <_PixelCandidate>[];
    final topInset = (height * 0.055).round();

    for (var y = topInset; y < height; y += sampleStep) {
      for (var x = 0; x < width; x += sampleStep) {
        final pixel = frame.getPixel(x, y);
        final brightness = _brightness(pixel);
        final saturation = _saturation(pixel);

        if (brightness > 0.69 && saturation < 0.23) {
          final contrast = _localContrast(frame, x, y, sampleStep * 5);
          final score = (brightness * 0.62) + (contrast * 0.38);
          if (score > 0.58) {
            candidates.add(_PixelCandidate(x: x, y: y, score: score));
          }
        }
      }
    }

    if (candidates.isEmpty) {
      return null;
    }

    final clusters = _clusterCandidates(
      candidates,
      sampleStep * 7,
      width,
      height,
    );
    if (clusters.isEmpty) {
      return null;
    }

    clusters.sort((a, b) => b.score.compareTo(a.score));
    final cluster = clusters.first;
    final diameter = cluster.diameter;
    final minDiameter = math.min(width, height) * 0.018;
    final maxDiameter = math.min(width, height) * 0.19;
    if (diameter < minDiameter || diameter > maxDiameter) {
      return null;
    }

    return TouchDetectionResult(
      frameIndex: frameIndex,
      target: RelativeTarget(
        x: (cluster.centerX / width).clamp(0, 1).toDouble(),
        y: (cluster.centerY / height).clamp(0, 1).toDouble(),
        width: (diameter * 1.55 / width).clamp(0.08, 0.24).toDouble(),
        height: (diameter * 1.55 / height).clamp(0.05, 0.16).toDouble(),
        label: '自动识别触摸点',
      ),
      confidence: cluster.score.clamp(0, 1).toDouble(),
    );
  }
}

class IsolateTouchIndicatorDetector implements TouchIndicatorDetector {
  const IsolateTouchIndicatorDetector({this.minConfidence = 0.2});

  final double minConfidence;

  @override
  Future<List<TouchDetectionResult>> detect(List<VideoFrame> frames) {
    return Isolate.run(
      () => TemporalTouchIndicatorDetector(
        minConfidence: minConfidence,
      ).detectSync(frames),
    );
  }
}

class _PixelCandidate {
  const _PixelCandidate({
    required this.x,
    required this.y,
    required this.score,
  });

  final int x;
  final int y;
  final double score;
}

class _Cluster {
  const _Cluster({
    required this.centerX,
    required this.centerY,
    required this.diameter,
    required this.score,
  });

  factory _Cluster.fromMembers(
    List<_PixelCandidate> members,
    int imageWidth,
    int imageHeight,
  ) {
    var weightedX = 0.0;
    var weightedY = 0.0;
    var totalWeight = 0.0;
    var minX = imageWidth;
    var minY = imageHeight;
    var maxX = 0;
    var maxY = 0;

    for (final member in members) {
      weightedX += member.x * member.score;
      weightedY += member.y * member.score;
      totalWeight += member.score;
      minX = math.min(minX, member.x);
      minY = math.min(minY, member.y);
      maxX = math.max(maxX, member.x);
      maxY = math.max(maxY, member.y);
    }

    final spreadX = math.max(1, maxX - minX);
    final spreadY = math.max(1, maxY - minY);
    final diameter = math.sqrt((spreadX * spreadX + spreadY * spreadY) / 2);
    final density = (members.length / math.max(1, diameter)).clamp(0, 1);
    final averageScore = totalWeight / members.length;

    return _Cluster(
      centerX: weightedX / totalWeight,
      centerY: weightedY / totalWeight,
      diameter: diameter,
      score: (averageScore * 0.78 + density * 0.22).clamp(0, 1).toDouble(),
    );
  }

  final double centerX;
  final double centerY;
  final double diameter;
  final double score;
}

List<_Cluster> _clusterCandidates(
  List<_PixelCandidate> candidates,
  int radius,
  int imageWidth,
  int imageHeight,
) {
  final clusters = <_Cluster>[];
  final visited = List<bool>.filled(candidates.length, false);
  final radiusSquared = radius * radius;

  for (var index = 0; index < candidates.length; index += 1) {
    if (visited[index]) {
      continue;
    }

    final queue = <int>[index];
    visited[index] = true;
    final members = <_PixelCandidate>[];

    while (queue.isNotEmpty) {
      final currentIndex = queue.removeLast();
      final current = candidates[currentIndex];
      members.add(current);

      for (
        var otherIndex = 0;
        otherIndex < candidates.length;
        otherIndex += 1
      ) {
        if (visited[otherIndex]) {
          continue;
        }
        final other = candidates[otherIndex];
        final dx = current.x - other.x;
        final dy = current.y - other.y;
        if (dx * dx + dy * dy <= radiusSquared) {
          visited[otherIndex] = true;
          queue.add(otherIndex);
        }
      }
    }

    if (members.length >= 3) {
      clusters.add(_Cluster.fromMembers(members, imageWidth, imageHeight));
    }
  }

  return clusters;
}

double _localContrast(image.Image frame, int x, int y, int radius) {
  final centerBrightness = _brightness(frame.getPixel(x, y));
  var totalDelta = 0.0;
  var samples = 0;

  for (final offset in [
    math.Point(-radius, 0),
    math.Point(radius, 0),
    math.Point(0, -radius),
    math.Point(0, radius),
    math.Point(-radius, -radius),
    math.Point(radius, radius),
  ]) {
    final sx = (x + offset.x).clamp(0, frame.width - 1).toInt();
    final sy = (y + offset.y).clamp(0, frame.height - 1).toInt();
    totalDelta += (centerBrightness - _brightness(frame.getPixel(sx, sy)))
        .abs();
    samples += 1;
  }

  return samples == 0 ? 0 : (totalDelta / samples).clamp(0, 1).toDouble();
}

double _brightness(image.Pixel pixel) {
  return (pixel.r + pixel.g + pixel.b) / (255 * 3);
}

double _saturation(image.Pixel pixel) {
  final r = pixel.r.toInt();
  final g = pixel.g.toInt();
  final b = pixel.b.toInt();
  final maxChannel = math.max(r, math.max(g, b));
  final minChannel = math.min(r, math.min(g, b));
  return (maxChannel - minChannel) / 255;
}

double _colorDelta(image.Pixel a, image.Pixel b) {
  final dr = (a.r - b.r).abs() / 255;
  final dg = (a.g - b.g).abs() / 255;
  final db = (a.b - b.b).abs() / 255;
  return (dr + dg + db) / 3;
}
