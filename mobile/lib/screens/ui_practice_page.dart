import 'package:flutter/material.dart';

import '../models/ui_description.dart';
import '../widgets/ui_builder.dart';

class UIPracticePage extends StatefulWidget {
  const UIPracticePage({
    super.key,
    required this.page,
    required this.targetCount,
  });

  final UIPage page;
  final int targetCount;

  @override
  State<UIPracticePage> createState() => _UIPracticePageState();
}

class _UIPracticePageState extends State<UIPracticePage> {
  int _currentStep = 1;
  int _correctCount = 0;
  int _wrongCount = 0;
  String? _feedbackText;
  Color? _feedbackColor;

  void _handleTargetTap(UIWidget target) {
    final expectedStep = target.stepIndex ?? _currentStep;

    if (expectedStep == _currentStep) {
      setState(() {
        _correctCount++;
        _feedbackText = '✓ 正确！${target.instruction ?? "很好！"}';
        _feedbackColor = Colors.green;
      });

      if (_currentStep >= widget.targetCount) {
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) _showCompletionDialog();
        });
      } else {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            setState(() {
              _currentStep++;
              _feedbackText = null;
              _feedbackColor = null;
            });
          }
        });
      }
    } else {
      setState(() {
        _wrongCount++;
        _feedbackText = '✗ 不对哦，请按顺序点击';
        _feedbackColor = Colors.red;
      });
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) {
          setState(() {
            _feedbackText = null;
            _feedbackColor = null;
          });
        }
      });
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 32),
            SizedBox(width: 10),
            Text('练习完成', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ScoreRow(label: '正确', value: _correctCount, color: Colors.green),
            const SizedBox(height: 6),
            _ScoreRow(label: '错误', value: _wrongCount, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _wrongCount == 0
                  ? '太棒了！全部点对了！🎉'
                  : '继续加油，多练几次就熟了 💪',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appBar = widget.page.appBar;
    final bgColor = UIBuilder.parseColor(widget.page.backgroundColor);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(
          appBar?.title ?? widget.page.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: appBar?.showBackButton == true
            ? const Icon(Icons.arrow_back_ios_new, size: 20)
            : null,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MiniChip(
                  icon: Icons.check,
                  value: _correctCount,
                  color: Colors.green,
                ),
                const SizedBox(width: 6),
                _MiniChip(
                  icon: Icons.close,
                  value: _wrongCount,
                  color: Colors.red,
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Step progress
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(
              children: [
                for (var i = 1; i <= widget.targetCount; i++)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: i < _currentStep
                            ? Colors.green
                            : i == _currentStep
                                ? const Color(0xFF007AFF)
                                : Colors.grey.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Step indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text(
              '第 $_currentStep 步 / 共 ${widget.targetCount} 步',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Reconstructed UI
          Expanded(
            child: SingleChildScrollView(
              child: UIBuilder(
                widget: widget.page.body,
                interactive: true,
                currentStepIndex: _currentStep,
                onTargetTap: _handleTargetTap,
              ),
            ),
          ),
          // Feedback bar
          if (_feedbackText != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: (_feedbackColor ?? Colors.grey).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _feedbackText!,
                style: TextStyle(
                  color: _feedbackColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final int value;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 3),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 16)),
        const Spacer(),
        Text(
          '$value 次',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
