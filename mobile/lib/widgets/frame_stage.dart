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
    this.onTapRelative,
    this.interactive = false,
    this.hitRadius = 0.20,
    this.onPracticeResult,
  });

  final VideoFrame frame;
  final double aspectRatio;
  final RelativeTarget? target;
  final ProcessedButton? processedButton;
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
      if (widget.interactive) {
        _pulseController.repeat();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeAspectRatio =
        widget.aspectRatio > 0 ? widget.aspectRatio : 9 / 16;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: safeAspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final darkOverlay =
                widget.interactive && _feedback == TapFeedback.none;

            final child = Stack(
              fit: StackFit.expand,
              children: [
                // Base image
                Image.memory(widget.frame.bytes, fit: BoxFit.cover),

                // Dim the background in practice mode to make target pop
                if (darkOverlay)
                  Container(color: Colors.black.withValues(alpha: 0.15)),

                // Target overlay
                if (widget.target != null)
                  widget.processedButton != null
                      ? _BlurredButtonOverlay(
                          target: widget.target!,
                          processedButton: widget.processedButton!,
                          feedback: _feedback,
                          pulseAnimation:
                              darkOverlay ? _pulseAnimation : null,
                        )
                      : _TargetOverlay(
                          target: widget.target!,
                          feedback: _feedback,
                        ),

                // Correct feedback
                if (_feedback == TapFeedback.correct)
                  const _CorrectOverlay(),

                // Wrong flash
                if (_feedback == TapFeedback.wrong)
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        color: Colors.red.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
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

// ── Blurred button overlay (macOS frosted-glass style) ──────────

class _BlurredButtonOverlay extends StatelessWidget {
  const _BlurredButtonOverlay({
    required this.target,
    required this.processedButton,
    required this.feedback,
    this.pulseAnimation,
  });

  final RelativeTarget target;
  final ProcessedButton processedButton;
  final TapFeedback feedback;
  final Animation<double>? pulseAnimation;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imgW = processedButton.displayWidth;
        final imgH = processedButton.displayHeight;
        // Scale the display to fit within the container while keeping
        // the enlarged button centered on the target
        final scaleX = constraints.maxWidth / imgW;
        final scaleY = constraints.maxHeight / imgH;
        final scale = (scaleX < scaleY ? scaleX : scaleY) * 0.85;

        final displayW = imgW * scale;
        final displayH = imgH * scale;
        final left = (target.x * constraints.maxWidth) - displayW / 2;
        final top = (target.y * constraints.maxHeight) - displayH / 2;

        final isCorrect = feedback == TapFeedback.correct;

        Widget overlay = AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          width: displayW.clamp(0, constraints.maxWidth),
          height: displayH.clamp(0, constraints.maxHeight),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: isCorrect
                    ? Colors.green.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.25),
                blurRadius: isCorrect ? 28 : 20,
                spreadRadius: isCorrect ? 4 : 0,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: RawImage(
              image: processedButton.blurredImage,
              fit: BoxFit.fill,
              width: displayW,
              height: displayH,
            ),
          ),
        );

        // Pulse animation for practice mode
        if (pulseAnimation != null && !isCorrect) {
          overlay = AnimatedBuilder(
            animation: pulseAnimation!,
            builder: (context, child) {
              final pulse = pulseAnimation!.value;
              return Transform.scale(
                scale: 1.0 + pulse * 0.04,
                child: child,
              );
            },
            child: overlay,
          );
        }

        return Stack(
          children: [
            Positioned(
              left: left.clamp(0, constraints.maxWidth - displayW).toDouble(),
              top: top.clamp(0, constraints.maxHeight - displayH).toDouble(),
              child: overlay,
            ),
            // Arrow hint below the button
            if (pulseAnimation != null && !isCorrect)
              Positioned(
                left: target.x * constraints.maxWidth - 15,
                top: (top + displayH + 4).clamp(0, constraints.maxHeight - 32),
                child: AnimatedBuilder(
                  animation: pulseAnimation!,
                  builder: (context, child) {
                    return Opacity(
                      opacity: 0.5 + pulseAnimation!.value * 0.5,
                      child: child,
                    );
                  },
                  child: const Icon(
                    Icons.keyboard_arrow_up,
                    color: Colors.white,
                    size: 32,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Fallback target overlay (simple colored box) ─────────────────

class _TargetOverlay extends StatefulWidget {
  const _TargetOverlay({
    required this.target,
    this.feedback = TapFeedback.none,
  });

  final RelativeTarget target;
  final TapFeedback feedback;

  @override
  State<_TargetOverlay> createState() => _TargetOverlayState();
}

class _TargetOverlayState extends State<_TargetOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _glowAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.6, end: 1.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.6), weight: 1),
    ]).animate(_glowController);
    _glowController.repeat();
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.target.width ?? 0.24;
    final height = widget.target.height ?? 0.16;

    Color borderColor;
    Color fillColor;
    IconData icon;

    switch (widget.feedback) {
      case TapFeedback.correct:
        borderColor = Colors.greenAccent;
        fillColor = Colors.green.withValues(alpha: 0.22);
        icon = Icons.check_circle;
      case TapFeedback.wrong:
        borderColor = Colors.redAccent;
        fillColor = Colors.red.withValues(alpha: 0.14);
        icon = Icons.touch_app;
      case TapFeedback.none:
        borderColor = Colors.white.withValues(alpha: 0.9);
        fillColor = const Color(0xFF007AFF).withValues(alpha: 0.15);
        icon = Icons.touch_app;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.maxWidth * width;
        final boxHeight = constraints.maxHeight * height;
        final left = (widget.target.x * constraints.maxWidth) - boxWidth / 2;
        final top =
            (widget.target.y * constraints.maxHeight) - boxHeight / 2;

        return AnimatedBuilder(
          animation: _glowAnimation,
          builder: (context, child) {
            return Stack(
              children: [
                Positioned(
                  left: left
                      .clamp(0, constraints.maxWidth - boxWidth)
                      .toDouble(),
                  top: top
                      .clamp(0, constraints.maxHeight - boxHeight)
                      .toDouble(),
                  width: boxWidth,
                  height: boxHeight,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: fillColor,
                      border: Border.all(
                        color: borderColor,
                        width: widget.feedback == TapFeedback.none ? 2.5 : 3,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: borderColor.withValues(
                            alpha: 0.3 * _glowAnimation.value,
                          ),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        icon,
                        color: Colors.white.withValues(alpha: 0.9),
                        size: 32,
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
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _fadeAnimation.value,
            child: Container(
              color: Colors.black.withValues(alpha: 0.20),
              child: Center(
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 36,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B5E20).withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
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
                          size: 56,
                        ),
                        SizedBox(height: 10),
                        Text(
                          '点对了！',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
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
