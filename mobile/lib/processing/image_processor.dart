import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/button_analysis.dart';

class ProcessedButton {
  const ProcessedButton({
    required this.blurredImage,
    required this.displayWidth,
    required this.displayHeight,
  });

  final ui.Image blurredImage;
  final double displayWidth;
  final double displayHeight;
}

class ImageProcessor {
  const ImageProcessor();

  /// Extracts the button region from source image, applies gaussian blur to
  /// the background, enlarges the button, and adds a soft glow border.
  Future<ProcessedButton> extractBlurredButton({
    required Uint8List sourceBytes,
    required BoundingBox boundingBox,
    double scale = 1.5,
    int blurRadius = 14,
  }) async {
    final source = img.decodeImage(sourceBytes);
    if (source == null) {
      throw ArgumentError('Failed to decode source image.');
    }

    final srcW = source.width;
    final srcH = source.height;

    // Calculate pixel region from relative coordinates
    final boxW = (boundingBox.width * srcW).round().clamp(1, srcW).toInt();
    final boxH = (boundingBox.height * srcH).round().clamp(1, srcH).toInt();
    final boxX = ((boundingBox.x * srcW - boxW / 2)
        .round()
        .clamp(0, srcW - boxW)
        .toInt());
    final boxY = ((boundingBox.y * srcH - boxH / 2)
        .round()
        .clamp(0, srcH - boxH)
        .toInt());

    // Enlarge the crop region to include surrounding context
    const expandFactor = 1.8;
    final expandW = (boxW * expandFactor).round();
    final expandH = (boxH * expandFactor).round();
    final expandX =
        (boxX + boxW / 2 - expandW / 2).round().clamp(0, srcW - expandW).toInt();
    final expandY =
        (boxY + boxH / 2 - expandH / 2).round().clamp(0, srcH - expandH).toInt();

    // Crop the expanded region
    final cropRegion = img.copyCrop(
      source,
      x: expandX,
      y: expandY,
      width: expandW,
      height: expandH,
    );

    // Apply gaussian blur
    final blurred = img.gaussianBlur(cropRegion, radius: blurRadius);

    // Resize to scaled size
    final scaledW = (expandW * scale).round();
    final scaledH = (expandH * scale).round();
    final scaled = img.copyResize(
      blurred,
      width: scaledW,
      height: scaledH,
      interpolation: img.Interpolation.linear,
    );

    // Add glow border
    final withGlow = _addGlowBorder(scaled);

    // Convert to ui.Image
    final rgba = Uint8List.fromList(img.encodePng(withGlow));
    final codec = await ui.instantiateImageCodec(rgba);
    final frame = await codec.getNextFrame();

    return ProcessedButton(
      blurredImage: frame.image,
      displayWidth: withGlow.width.toDouble(),
      displayHeight: withGlow.height.toDouble(),
    );
  }

  img.Image _addGlowBorder(img.Image input) {
    final w = input.width;
    final h = input.height;
    final border = 8;
    final outW = w + border * 2;
    final outH = h + border * 2;

    final output = img.Image(width: outW, height: outH);
    img.fill(output, color: img.ColorRgba8(0, 0, 0, 0));

    // Draw soft glow layers
    for (var layer = border; layer > 0; layer -= 2) {
      final alpha = (40 * layer / border).round();
      final glowColor = img.ColorRgba8(255, 255, 255, alpha);
      img.fillRect(
        output,
        x1: border - layer,
        y1: border - layer,
        x2: outW - border + layer,
        y2: outH - border + layer,
        color: glowColor,
        radius: (math.min(w, h) * 0.15).round().toDouble(),
      );
    }

    // Composite input on top
    img.compositeImage(output, input, dstX: border, dstY: border);

    // Round corners
    final radius = (math.min(outW, outH) * 0.12).round();
    return _roundCorners(output, radius);
  }

  img.Image _roundCorners(img.Image input, int radius) {
    final w = input.width;
    final h = input.height;
    for (var y = 0; y < radius; y++) {
      for (var x = 0; x < radius; x++) {
        final dx = radius - x;
        final dy = radius - y;
        if (dx * dx + dy * dy > radius * radius) {
          input.setPixelRgba(x, y, 0, 0, 0, 0); // top-left
          input.setPixelRgba(w - 1 - x, y, 0, 0, 0, 0); // top-right
          input.setPixelRgba(x, h - 1 - y, 0, 0, 0, 0); // bottom-left
          input.setPixelRgba(w - 1 - x, h - 1 - y, 0, 0, 0, 0); // bottom-right
        }
      }
    }
    return input;
  }

  /// Parse hex color string to Flutter Color
  static Color parseColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length == 6) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    if (cleaned.length == 8) {
      return Color(int.parse(cleaned, radix: 16));
    }
    return const Color(0xFF007AFF);
  }
}
