import 'package:flutter/material.dart';

import '../models/lesson.dart';
import '../models/video_frame.dart';

enum TapFeedback { none, correct, wrong }

class FrameStage extends StatefulWidget {
  const FrameStage({
    super.key,
    required this.frame,
    required this.aspectRatio,
    this.target,
    this.onTapRelative,
    this.interactive = false,
    this.hitRadius = 0.12,
    this.onPracticeResult,
  });

  final VideoFrame frame;
  final double aspectRatio;
  final RelativeTarget? target;
  final ValueChanged<Offset>? onTapRelative;
  final bool interactive;
  final double hitRadius;
  final ValueChanged<bool>? onPracticeResult;

  @override
  State<FrameStage> createState() => _FrameStageState();
}

class _FrameStageState extends State<FrameStage>
    with SingleTickerProviderStateMixin {
  TapFeedback _feedback = TapFeedback.none;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -5), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -5, end: 5), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 5, end: 0), weight: 2),
    ]).animate(_shakeController);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details, BoxConstraints constraints) {
    if (!widget.interactive || _feedback == TapFeedback.correct) {
      widget.onTapRelative?.call(
        Offset(
          (details.localPosition.dx / constraints.maxWidth).clamp(0, 1),
          (details.localPosition.dy / constraints.maxHeight).clamp(0, 1),
        ),
      );
      return;
    }

    final tapX = details.localPosition.dx / constraints.maxWidth;
    final tapY = details.localPosition.dy / constraints.maxHeight;
    final target = widget.target;

    final hit = target != null && _isWithinTarget(tapX, tapY, target);

    if (hit) {
      setState(() {
        _feedback = TapFeedback.correct;
      });
      widget.onPracticeResult?.call(true);
    } else {
      setState(() {
        _feedback = TapFeedback.wrong;
      });
      _shakeController.forward(from: 0);
      widget.onPracticeResult?.call(false);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && _feedback == TapFeedback.wrong) {
          setState(() {
            _feedback = TapFeedback.none;
          });
        }
      });
    }
  }

  bool _isWithinTarget(double tx, double ty, RelativeTarget target) {
    final halfW = (target.width ?? widget.hitRadius) / 2;
    final halfH = (target.height ?? widget.hitRadius) / 2;
    return (tx - target.x).abs() <= halfW &&
        (ty - target.y).abs() <= halfH;
  }

  void resetFeedback() {
    if (mounted) {
      setState(() {
        _feedback = TapFeedback.none;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeAspectRatio = widget.aspectRatio > 0 ? widget.aspectRatio : 9 / 16;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: safeAspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final child = Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(widget.frame.bytes, fit: BoxFit.cover),
                if (widget.target != null)
                  _TargetOverlay(
                    target: widget.target!,
                    feedback: _feedback,
                  ),
                if (_feedback == TapFeedback.correct)
                  const _CorrectOverlay(),
              ],
            );

            Widget result = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _handleTapDown(details, constraints),
              child: child,
            );

            if (_feedback == TapFeedback.wrong) {
              result = AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(_shakeAnimation.value, 0),
                    child: child,
                  );
                },
                child: result,
              );
            }

            return result;
          },
        ),
      ),
    );
  }
}

class _TargetOverlay extends StatelessWidget {
  const _TargetOverlay({
    required this.target,
    this.feedback = TapFeedback.none,
  });

  final RelativeTarget target;
  final TapFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final width = target.width ?? 0.18;
    final height = target.height ?? 0.09;

    Color borderColor;
    Color fillColor;
    IconData icon;

    switch (feedback) {
      case TapFeedback.correct:
        borderColor = Colors.greenAccent;
        fillColor = Colors.green.withValues(alpha: 0.28);
        icon = Icons.check_circle;
      case TapFeedback.wrong:
        borderColor = Colors.redAccent;
        fillColor = Colors.red.withValues(alpha: 0.18);
        icon = Icons.touch_app;
      case TapFeedback.none:
        borderColor = Colors.redAccent;
        fillColor = Colors.red.withValues(alpha: 0.18);
        icon = Icons.touch_app;
    }

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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  color: fillColor,
                  border: Border.all(color: borderColor, width: 3),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.24),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(icon, color: Colors.white, size: 30),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CorrectOverlay extends StatelessWidget {
  const _CorrectOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.green.withValues(alpha: 0.12),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green, size: 72),
              SizedBox(height: 8),
              Text(
                '点击正确！',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
