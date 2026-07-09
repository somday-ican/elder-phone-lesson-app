import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../data/card_repository.dart';
import '../generation/model_client.dart';
import '../models/skill_card.dart';
import 'ui_practice_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.modelClient,
    this.cardRepository = const CardRepository(),
  });

  final ModelClient modelClient;
  final CardRepository cardRepository;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final AudioRecorder _recorder = AudioRecorder();
  bool _isListening = false;
  bool _isGenerating = false;
  int _generatingElapsed = 0;
  Timer? _generatingTimer;

  // Progress bar animation
  late AnimationController _progressCtrl;
  late Animation<double> _progressAnim;

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 80),
    );
    _progressAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.15), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.15, end: 0.45), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.45, end: 0.75), weight: 3),
      TweenSequenceItem(tween: Tween(begin: 0.75, end: 0.90), weight: 4),
    ]).animate(_progressCtrl);
  }

  Future<void> _generate() async {
    final goal = _textController.text.trim();
    if (goal.isEmpty || _isGenerating) return;

    _focusNode.unfocus();
    setState(() {
      _isGenerating = true;
      _generatingElapsed = 0;
    });
    // Defer animation to next frame to avoid framework assertion
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _progressCtrl.forward(from: 0);
    });

    // Timer for elapsed seconds display
    _generatingTimer?.cancel();
    _generatingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _generatingElapsed++);
    });

    try {
      final result = await widget.modelClient.chatGenerate(goal: goal);
      _generatingTimer?.cancel();
      if (!mounted) return;

      final card = SkillCard.create(
        title: result.title,
        html: result.html,
        stepCount: result.steps.length,
      );

      await widget.cardRepository.add(card);
      _textController.clear();

      // Complete the progress bar
      _progressCtrl.stop();
      setState(() {
        _isGenerating = false;
      });
      _openCard(card);
    } catch (error) {
      _generatingTimer?.cancel();
      _progressCtrl.stop();
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '生成失败：${error.toString().replaceFirst("Exception: ", "")}',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _screenshotToCard() async {
    if (_isGenerating || _isListening) return;
    // Pick images first (limit 3 for proxy stability)
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 50);
    if (files.isEmpty) return;
    if (!mounted) return;

    // Ask for goal
    final goalCtrl = TextEditingController();
    final goal = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('这些截图是做什么的？'),
        content: TextField(
          controller: goalCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '比如：我要给孙子打微信视频'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, goalCtrl.text.trim()),
            child: const Text('生成'),
          ),
        ],
      ),
    );
    goalCtrl.dispose();
    if (!mounted) return;
    if (goal == null || goal.isEmpty) return;
    final goalText = goal; // narrow to non-null

    // Compress images to base64
    setState(() {
      _isGenerating = true;
      _generatingElapsed = 0;
    });
    // Defer animation to next frame to avoid framework assertion
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _progressCtrl.forward(from: 0);
    });
    _generatingTimer?.cancel();
    _generatingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _generatingElapsed++);
    });

    try {
      final base64s = <String>[];
      for (final f in files) {
        final bytes = await File(f.path).readAsBytes();
        // Aggressively compress for proxy stability (270px, JPEG Q50)
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          const maxW = 270;
          final resized = decoded.width > maxW
              ? img.copyResize(
                  decoded,
                  width: maxW,
                  height: (decoded.height * maxW / decoded.width).round(),
                )
              : decoded;
          final compressed = img.encodeJpg(resized, quality: 50);
          base64s.add('data:image/jpeg;base64,${base64Encode(compressed)}');
        } else {
          base64s.add('data:image/jpeg;base64,${base64Encode(bytes)}');
        }
      }

      final result = await widget.modelClient.chatGenerate(
        goal: goalText,
        screenshotBase64s: base64s,
      );
      _generatingTimer?.cancel();
      if (!mounted) return;

      final card = SkillCard.create(
        title: result.title,
        html: result.html,
        stepCount: result.steps.length,
      );
      await widget.cardRepository.add(card);
      _progressCtrl.stop();
      setState(() => _isGenerating = false);
      _openCard(card);
    } catch (error) {
      _generatingTimer?.cancel();
      _progressCtrl.stop();
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('生成失败：$error'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _startVoice() async {
    if (_isListening || _isGenerating) return;
    if (!await _recorder.hasPermission()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('需要麦克风权限'), behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _isListening = true);
    try {
      final filePath = '${Directory.systemTemp.path}/voice_input.m4a';
      final aacOk = await _recorder.isEncoderSupported(AudioEncoder.aacLc);
      await _recorder.start(RecordConfig(encoder: aacOk ? AudioEncoder.aacLc : AudioEncoder.aacHe, sampleRate: 16000, numChannels: 1, bitRate: aacOk ? 64000 : 32000), path: filePath);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) { await _recorder.stop(); return; }
      final shouldStop = await showDialog<bool>(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(children: [Icon(Icons.mic, color: Colors.red, size: 28), SizedBox(width: 10), Text('正在聆听...', style: TextStyle(fontWeight: FontWeight.w800))]),
        content: const Text('请说出你想学的操作，说完后点击"完成"', style: TextStyle(fontSize: 20)),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF6B35)), child: const Text('完成'))],
      ));
      final actualPath = await _recorder.stop();
      setState(() => _isListening = false);
      if (shouldStop != true || !mounted) return;
      final audioFile = File(actualPath ?? filePath);
      if (!await audioFile.exists()) { _showSnack('录音文件未生成'); return; }
      final bytes = await audioFile.readAsBytes();
      if (bytes.length < 400) { _showSnack('录音太短，请说完整句话'); audioFile.delete().ignore(); return; }
      final text = await widget.modelClient.transcribeAudio(audioBase64: base64Encode(bytes));
      audioFile.delete().ignore();
      if (!mounted || text.isEmpty) { _showSnack('未识别到语音，请说清楚一点再试'); return; }
      _textController.text = text;
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) _generate();
    } catch (e) { if (mounted) { setState(() => _isListening = false); _showSnack('录音失败：$e'); } }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontSize: 18)), behavior: SnackBarBehavior.floating, backgroundColor: Colors.red.shade700));
  }

  void _openCard(SkillCard card) {
    widget.cardRepository.incrementPractice(card.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UIPracticePage(
          html: card.html,
          title: card.title,
          targetCount: card.stepCount,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _generatingTimer?.cancel();
    _progressCtrl.dispose();
    // Voice is system dialog — no cleanup needed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeroHeader(),
            if (_isGenerating) _buildProgressBar(),
            Expanded(child: _buildVoiceFirstHome()),
            const _BottomNavBar(currentIndex: 0),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader() {
    return Container(
      height: 128,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
      color: const Color(0xFFFFF8F0),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '阿姨，早上好',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 28,
                      height: 1.12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '您已连续学习3天，真棒！',
                    style: TextStyle(
                      color: Color(0xFFFF6B35),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '通知',
              onPressed: () {},
              icon: Badge(
                smallSize: 12,
                backgroundColor: Colors.red,
                child: Icon(
                  Icons.notifications_none_rounded,
                  color: Colors.grey.shade700,
                  size: 32,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Smooth animated progress bar ──────────────────────────────

  Widget _buildProgressBar() {
    final minutes = _generatingElapsed ~/ 60;
    final seconds = _generatingElapsed % 60;
    final timeStr = minutes > 0 ? '$minutes分$seconds秒' : '$seconds秒';

    return AnimatedBuilder(
      animation: _progressAnim,
      builder: (context, child) {
        final progress = _progressAnim.value;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF007AFF).withValues(alpha: 0.05),
            border: Border(
              bottom: BorderSide(
                color: const Color(0xFF007AFF).withValues(alpha: 0.1),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(
                        const Color(0xFF007AFF).withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'AI 正在生成教程',
                    style: TextStyle(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    timeStr,
                    style: TextStyle(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.5),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        width:
                            progress * (MediaQuery.of(context).size.width - 40),
                        height: 4,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF007AFF),
                              const Color(0xFF007AFF).withValues(alpha: 0.7),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF007AFF,
                              ).withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${(progress * 100).round()}%',
                  style: TextStyle(
                    fontSize: 11,
                    color: const Color(0xFF007AFF).withValues(alpha: 0.4),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVoiceFirstHome() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 34).clamp(0, double.infinity),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 420),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 34,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: _isListening
                          ? const Color(0xFF003366).withValues(alpha: 0.42)
                          : const Color(0xFF003366),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF6B35).withValues(alpha: 0.15),
                        blurRadius: 25,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: const Color(
                          0xFF003366,
                        ).withValues(alpha: _isListening ? 0.34 : 0.16),
                        blurRadius: _isListening ? 20 : 5,
                      ),
                    ],
                  ),
                  child: Text(
                    _isGenerating
                        ? '正在帮您生成教程...'
                        : _isListening
                        ? '我在听，慢慢说'
                        : '按下面，对我说：\n想学什么？',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isGenerating || _isListening
                          ? const Color(0xFF003366)
                          : Colors.grey.shade400,
                      fontSize: 24,
                      height: 1.42,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: _isListening
                        ? Colors.red.shade500
                        : const Color(0xFFFF6B35),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF6B35).withValues(alpha: 0.36),
                        blurRadius: _isListening ? 28 : 18,
                        spreadRadius: _isListening ? 14 : 2,
                      ),
                      const BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 16,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: IconButton(
                    tooltip: '语音输入',
                    onPressed: _isGenerating || _isListening
                        ? null
                        : _startVoice,
                    icon: const Icon(
                      Icons.mic_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _isGenerating ? '生成中，请稍等' : '点击说话',
                  style: const TextStyle(
                    color: Color(0xFF003366),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: _SecondaryAction(
                        icon: Icons.keyboard_rounded,
                        label: '打字输入',
                        onTap: _isGenerating ? null : _showTextInputSheet,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SecondaryAction(
                        icon: Icons.add_photo_alternate_outlined,
                        label: '上传截图',
                        onTap: _isGenerating ? null : _screenshotToCard,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/screenshot'),
                  icon: const Icon(Icons.collections_outlined),
                  label: const Text('打开图片教程生成器'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showTextInputSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '您想学什么？',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _textController,
                focusNode: _focusNode,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: '比如：我要给孙子打微信视频',
                  filled: true,
                  fillColor: const Color(0xFFFFF8F0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: () =>
                      Navigator.pop(ctx, _textController.text.trim()),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('生成教程'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || result == null || result.isEmpty) return;
    _textController.text = result;
    await _generate();
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 22),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF003366),
          side: const BorderSide(color: Color(0xFF003366), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({required this.currentIndex});
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        border: Border(
          top: BorderSide(
            color: Colors.black.withValues(alpha: 0.10),
            width: 2,
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        32,
        12,
        32,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            icon: Icons.home_outlined,
            label: '首页',
            active: currentIndex == 0,
            onTap: () {},
          ),
          _NavItem(
            icon: Icons.military_tech_rounded,
            label: '成就',
            active: false,
            onTap: () {
              Navigator.of(context).pushNamed('/achievements');
            },
          ),
          _NavItem(
            icon: Icons.person_outline_rounded,
            label: '我的',
            active: false,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 30,
              color: active ? const Color(0xFFFF6B35) : Colors.black,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: active ? const Color(0xFFFF6B35) : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
