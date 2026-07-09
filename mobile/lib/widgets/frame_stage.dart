import 'package:flutter/material.dart';

import '../models/lesson.dart';
import '../models/video_frame.dart';
import '../processing/image_processor.dart';

enum TapFeedback { none, correct, wrong }

class FrameStage extends StatefulWidget {
  const FrameStage({
    super.key,
    required this.frame,
    required this.aspectRatio,
    this.target,
    this.processedButton,
    this.buttonLabel,
    this.onTapRelative,
    this.interactive = false,
    this.hitRadius = 0.20,
    this.onPracticeResult,
  });

  final VideoFrame frame;
  final double aspectRatio;
  final RelativeTarget? target;
  final ProcessedButton? processedButton;
  final String? buttonLabel;
  final ValueChanged<Offset>? onTapRelative;
  final bool interactive;
  final double hitRadius;
  final ValueChanged<bool>? onPracticeResult;

  @override
  State<FrameStage> createState() => _FrameStageState();
}

class _FrameStageState extends State<FrameStage>
    with TickerProviderStateMixin {
  TapFeedback _feedback = TapFeedback.none;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -5), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -5, end: 5), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 5, end: 0), weight: 2),
    ]).animate(_shakeController);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _pulseAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 1),
    ]).animate(_pulseController);

    if (widget.interactive && widget.target != null) {
      _pulseController.repeat();
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _pulseController.dispose();
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
      _pulseController.stop();
      setState(() => _feedback = TapFeedback.correct);
      widget.onPracticeResult?.call(true);
    } else {
      setState(() => _feedback = TapFeedback.wrong);
      _shakeController.forward(from: 0);
      widget.onPracticeResult?.call(false);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && _feedback == TapFeedback.wrong) {
          setState(() => _feedback = TapFeedback.none);
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
      setState(() => _feedback = TapFeedback.none);
      if (widget.interactive) _pulseController.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeAspectRatio =
        widget.aspectRatio > 0 ? widget.aspectRatio : 9 / 16;
    final darkOverlay =
        widget.interactive && _feedback == TapFeedback.none;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: safeAspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final child = Stack(
              fit: StackFit.expand,
              children: [
                // Base screenshot
                Image.memory(widget.frame.bytes, fit: BoxFit.cover),

                // Dim background in practice mode
                if (darkOverlay)
                  Container(color: Colors.black.withValues(alpha: 0.20)),

                // Target highlight
                if (widget.target != null)
                  widget.processedButton != null
                      ? _ButtonCutoutOverlay(
                          target: widget.target!,
                          processedButton: widget.processedButton!,
                          label: widget.buttonLabel,
                          feedback: _feedback,
                          pulseAnimation:
                              darkOverlay ? _pulseAnimation : null,
                        )
                      : _SimpleHighlightOverlay(
                          target: widget.target!,
                          label: widget.buttonLabel,
                          feedback: _feedback,
                          pulseAnimation:
                              darkOverlay ? _pulseAnimation : null,
                        ),

                // Correct feedback
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

// ── Button cutout overlay (shows actual button cropped from screenshot) ──

class _ButtonCutoutOverlay extends StatelessWidget {
  const _ButtonCutoutOverlay({
    required this.target,
    required this.processedButton,
    required this.feedback,
    this.label,
    this.pulseAnimation,
  });

  final RelativeTarget target;
  final ProcessedButton processedButton;
  final TapFeedback feedback;
  final String? label;
  final Animation<double>? pulseAnimation;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imgW = processedButton.displayWidth;
        final imgH = processedButton.displayHeight;
        final scaleX = constraints.maxWidth / imgW;
        final scaleY = constraints.maxHeight / imgH;
        final scale = (scaleX < scaleY ? scaleX : scaleY) * 0.78;

        final displayW = imgW * scale;
        final displayH = imgH * scale;
        final left = (target.x * constraints.maxWidth) - displayW / 2;
        final top = (target.y * constraints.maxHeight) - displayH / 2;

        final isCorrect = feedback == TapFeedback.correct;

        Widget overlay = Container(
          width: displayW.clamp(0, constraints.maxWidth),
          height: displayH.clamp(0, constraints.maxHeight),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: isCorrect
                    ? Colors.green.withValues(alpha: 0.5)
                    : const Color(0xFF007AFF).withValues(alpha: 0.40),
                blurRadius: isCorrect ? 30 : 24,
                spreadRadius: isCorrect ? 6 : 2,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: RawImage(
              image: processedButton.buttonImage,
              fit: BoxFit.fill,
              width: displayW,
              height: displayH,
            ),
          ),
        );

        if (pulseAnimation != null && !isCorrect) {
          overlay = AnimatedBuilder(
            animation: pulseAnimation!,
            builder: (context, child) {
              final pulse = pulseAnimation!.value;
              return Transform.scale(
                scale: 1.0 + pulse * 0.06,
                child: child,
              );
            },
            child: overlay,
          );
        }

        return Stack(
          children: [
            Positioned(
              left: left.clamp(0, constraints.maxWidth - displayW),
              top: top.clamp(0, constraints.maxHeight - displayH),
              child: overlay,
            ),
            // Arrow hint
            if (pulseAnimation != null && !isCorrect)
              Positioned(
                left: target.x * constraints.maxWidth - 16,
                top: (top + displayH + 4)
                    .clamp(0, constraints.maxHeight - 30),
                child: AnimatedBuilder(
                  animation: pulseAnimation!,
                  builder: (context, child) {
                    return Opacity(
                      opacity: 0.5 + pulseAnimation!.value * 0.5,
                      child: child,
                    );
                  },
                  child: const Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: Colors.white,
                    size: 34,
                    shadows: [
                      Shadow(color: Colors.black54, blurRadius: 8),
                    ],
                  ),
                ),
              ),
            // Label below
            if (label != null && label!.isNotEmpty && pulseAnimation != null)
              Positioned(
                left: (target.x * constraints.maxWidth - 60)
                    .clamp(0, constraints.maxWidth - 120),
                top: (top + displayH + 32)
                    .clamp(0, constraints.maxHeight - 24),
                width: 120,
                child: Text(
                  label!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    shadows: [
                      Shadow(color: Colors.black54, blurRadius: 6),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Simple highlight overlay (fallback when no cutout image) ──

class _SimpleHighlightOverlay extends StatefulWidget {
  const _SimpleHighlightOverlay({
    required this.target,
    required this.feedback,
    this.label,
    this.pulseAnimation,
  });

  final RelativeTarget target;
  final TapFeedback feedback;
  final String? label;
  final Animation<double>? pulseAnimation;

  @override
  State<_SimpleHighlightOverlay> createState() =>
      _SimpleHighlightOverlayState();
}

class _SimpleHighlightOverlayState extends State<_SimpleHighlightOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowCtrl;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final width = target.width ?? 0.24;
    final height = target.height ?? 0.16;

    final isCorrect = widget.feedback == TapFeedback.correct;

    return LayoutBuilder(
      builder: (context, constraints) {
        final boxW = constraints.maxWidth * width;
        final boxH = constraints.maxHeight * height;
        final left =
            (target.x * constraints.maxWidth) - boxW / 2;
        final top =
            (target.y * constraints.maxHeight) - boxH / 2;

        return AnimatedBuilder(
          animation: _glowCtrl,
          builder: (context, child) {
            final glow = _glowCtrl.value;
            final borderColor = isCorrect
                ? Colors.greenAccent
                : const Color(0xFF007AFF);
            final fillColor = isCorrect
                ? Colors.green.withValues(alpha: 0.12)
                : const Color(0xFF007AFF).withValues(alpha: 0.08);

            return Stack(
              children: [
                Positioned(
                  left: left.clamp(0, constraints.maxWidth - boxW),
                  top: top.clamp(0, constraints.maxHeight - boxH),
                  width: boxW,
                  height: boxH,
                  child: Container(
                    decoration: BoxDecoration(
                      color: fillColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: borderColor.withValues(
                          alpha: 0.5 + glow * 0.5,
                        ),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: borderColor.withValues(
                            alpha: 0.2 + glow * 0.25,
                          ),
                          blurRadius: 20 + glow * 10,
                          spreadRadius: 1 + glow * 3,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: widget.label != null &&
                              widget.label!.isNotEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(4),
                              child: Text(
                                widget.label!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          : const Icon(
                              Icons.touch_app_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ── Correct feedback overlay ─────────────────────────────────────

class _CorrectOverlay extends StatefulWidget {
  const _CorrectOverlay();

  @override
  State<_CorrectOverlay> createState() => _CorrectOverlayState();
}

class _CorrectOverlayState extends State<_CorrectOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) {
          return Opacity(
            opacity: _scale.value.clamp(0, 1),
            child: Container(
              color: Colors.black.withValues(alpha: 0.25),
              child: Center(
                child: Transform.scale(
                  scale: _scale.value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 22,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B5E20)
                          .withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x4000C853),
                          blurRadius: 32,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF69F0AE),
                          size: 52,
                        ),
                        SizedBox(height: 8),
                        Text(
                          '点对了！',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
