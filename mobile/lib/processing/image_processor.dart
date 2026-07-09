import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ProcessedButton {
  const ProcessedButton({
    required this.buttonImage,
    required this.displayWidth,
    required this.displayHeight,
  });

  final ui.Image buttonImage;
  final double displayWidth;
  final double displayHeight;
}

class ImageProcessor {
  const ImageProcessor();

  /// Crops the button region from the screenshot, enlarges it slightly,
  /// adds a glowing border, and returns it as a ui.Image.
  ///
  /// This is designed to be simple and robust — it just crops the exact
  /// button area from the original image rather than trying to extract
  /// and re-composite it with a blurred background.
  Future<ProcessedButton> extractButton({
    required Uint8List sourceBytes,
    required double relX,
    required double relY,
    double relWidth = 0.20,
    double relHeight = 0.14,
    double scale = 1.4,
    Color glowColor = const Color(0xFF007AFF),
  }) async {
    final source = img.decodeImage(sourceBytes);
    if (source == null) {
      throw ArgumentError('Failed to decode source image.');
    }

    final srcW = source.width;
    final srcH = source.height;

    // Calculate pixel region from relative coords
    // Use generous minimum size so the button is always visible
    final minW = (srcW * 0.06).round();
    final minH = (srcH * 0.04).round();
    final boxW = (relWidth * srcW).round().clamp(minW, srcW ~/ 2);
    final boxH = (relHeight * srcH).round().clamp(minH, srcH ~/ 2);
    final boxX = ((relX * srcW) - boxW / 2).round().clamp(0, srcW - boxW);
    final boxY = ((relY * srcH) - boxH / 2).round().clamp(0, srcH - boxH);

    // Crop the button area
    final cropped = img.copyCrop(
      source,
      x: boxX,
      y: boxY,
      width: boxW,
      height: boxH,
    );

    // Scale up
    final scaledW = (boxW * scale).round();
    final scaledH = (boxH * scale).round();
    final scaled = img.copyResize(
      cropped,
      width: scaledW,
      height: scaledH,
      interpolation: img.Interpolation.cubic,
    );

    // Add a colored glow border
    final border = 6;
    final outW = scaledW + border * 2;
    final outH = scaledH + border * 2;

    final output = img.Image(width: outW, height: outH);
    img.fill(output, color: img.ColorRgba8(0, 0, 0, 0));

    // Draw glow layers from outer to inner
    final r = ((glowColor.r * 255).round()).clamp(0, 255);
    final g = ((glowColor.g * 255).round()).clamp(0, 255);
    final b = ((glowColor.b * 255).round()).clamp(0, 255);
    for (var layer = border; layer > 0; layer--) {
      final alpha = (60 * (border - layer + 1) / border).round();
      final c = img.ColorRgba8(r, g, b, alpha);
      img.fillRect(
        output,
        x1: border - layer,
        y1: border - layer,
        x2: outW - border + layer,
        y2: outH - border + layer,
        color: c,
        radius: 10,
      );
    }

    // Composite the cropped button on top of the glow
    img.compositeImage(output, scaled, dstX: border, dstY: border);

    // Round corners of the final image
    _roundCorners(output, 16);

    // Convert to ui.Image
    final rgba = Uint8List.fromList(img.encodePng(output));
    final codec = await ui.instantiateImageCodec(rgba);
    final frame = await codec.getNextFrame();

    return ProcessedButton(
      buttonImage: frame.image,
      displayWidth: outW.toDouble(),
      displayHeight: outH.toDouble(),
    );
  }

  void _roundCorners(img.Image input, int radius) {
    final w = input.width;
    final h = input.height;
    final r = radius.clamp(0, math.min(w, h) ~/ 2);
    for (var y = 0; y < r; y++) {
      for (var x = 0; x < r; x++) {
        final dx = r - x;
        final dy = r - y;
        if (dx * dx + dy * dy > r * r) {
          input.setPixelRgba(x, y, 0, 0, 0, 0);
          input.setPixelRgba(w - 1 - x, y, 0, 0, 0, 0);
          input.setPixelRgba(x, h - 1 - y, 0, 0, 0, 0);
          input.setPixelRgba(w - 1 - x, h - 1 - y, 0, 0, 0, 0);
        }
      }
    }
  }

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
