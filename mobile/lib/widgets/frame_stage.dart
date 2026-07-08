import 'package:flutter/material.dart';

import '../models/lesson.dart';
import '../models/video_frame.dart';

class FrameStage extends StatelessWidget {
  const FrameStage({
    super.key,
    required this.frame,
    required this.aspectRatio,
    this.target,
    this.onTapRelative,
  });

  final VideoFrame frame;
  final double aspectRatio;
  final RelativeTarget? target;
  final ValueChanged<Offset>? onTapRelative;

  @override
  Widget build(BuildContext context) {
    final safeAspectRatio = aspectRatio > 0 ? aspectRatio : 9 / 16;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: safeAspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: onTapRelative == null
                  ? null
                  : (details) {
                      onTapRelative!(
                        Offset(
                          (details.localPosition.dx / constraints.maxWidth)
                              .clamp(0, 1),
                          (details.localPosition.dy / constraints.maxHeight)
                              .clamp(0, 1),
                        ),
                      );
                    },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(frame.bytes, fit: BoxFit.cover),
                  if (target != null) _TargetOverlay(target: target!),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TargetOverlay extends StatelessWidget {
  const _TargetOverlay({required this.target});

  final RelativeTarget target;

  @override
  Widget build(BuildContext context) {
    final width = target.width ?? 0.18;
    final height = target.height ?? 0.09;

    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.maxWidth * width;
        final boxHeight = constraints.maxHeight * height;
        final left = (target.x * constraints.maxWidth) - boxWidth / 2;
        final top = (target.y * constraints.maxHeight) - boxHeight / 2;

        return Stack(
          children: [
            Positioned(
              left: left.clamp(0, constraints.maxWidth - boxWidth).toDouble(),
              top: top.clamp(0, constraints.maxHeight - boxHeight).toDouble(),
              width: boxWidth,
              height: boxHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.22),
                  border: Border.all(color: Colors.amberAccent, width: 3),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.24),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.touch_app, color: Colors.white, size: 30),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
