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
  List<SkillCard> _cards = [];
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
    _loadCards();
  }

  Future<void> _loadCards() async {
    final cards = await widget.cardRepository.loadAll();
    if (mounted) setState(() => _cards = cards);
  }

  Future<void> _generate() async {
    final goal = _textController.text.trim();
    if (goal.isEmpty || _isGenerating) return;

    _focusNode.unfocus();
    setState(() {
      _isGenerating = true;
      _generatingElapsed = 0;
    });

    // Start animated progress bar
    _progressCtrl.forward(from: 0);

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
      await _loadCards();
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
            content: Text('生成失败：${error.toString().replaceFirst("Exception: ", "")}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _screenshotToCard() async {
    // Pick images first
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 80);
    if (files.isEmpty) return;

    // Ask for goal
    final goalCtrl = TextEditingController();
    final goal = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('这些截图是做什么的？'),
        content: TextField(
          controller: goalCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '比如：我要给孙子打微信视频',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, goalCtrl.text.trim()), child: const Text('生成')),
        ],
      ),
    );
    goalCtrl.dispose();
    if (!mounted) return;
    if (goal == null || goal.isEmpty) return;
    final goalText = goal; // narrow to non-null

    // Compress images to base64
    setState(() { _isGenerating = true; _generatingElapsed = 0; });
    _progressCtrl.forward(from: 0);
    _generatingTimer?.cancel();
    _generatingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _generatingElapsed++);
    });

    try {
      final base64s = <String>[];
      for (final f in files) {
        final bytes = await File(f.path).readAsBytes();
        // Compress: resize to max 540px wide, JPEG quality 60
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          const maxW = 540;
          final resized = decoded.width > maxW
              ? img.copyResize(decoded, width: maxW,
                  height: (decoded.height * maxW / decoded.width).round())
              : decoded;
          final compressed = img.encodeJpg(resized, quality: 60);
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
      await _loadCards();
      _progressCtrl.stop();
      setState(() => _isGenerating = false);
      _openCard(card);
    } catch (error) {
      _generatingTimer?.cancel();
      _progressCtrl.stop();
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$error'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  Future<void> _startVoice() async {
    if (_isListening || _isGenerating) return;

    // Check permission first
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('需要麦克风权限才能使用语音输入'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Start recording
    setState(() => _isListening = true);
    try {
      final filePath = '${Directory.systemTemp.path}/voice_input.m4a';
      // WAV has broadest Android device support. aacLc is often unavailable on Chinese phones.
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1, bitRate: 64000),
        path: filePath,
      );

      // Short delay to ensure the recorder actually started
      await Future.delayed(const Duration(milliseconds: 500));

      // Show dialog to stop recording
      if (!mounted) {
        await _recorder.stop();
        return;
      }
      final shouldStop = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.mic, color: Colors.red, size: 28),
              SizedBox(width: 10),
              Text('正在聆听...'),
            ],
          ),
          content: const Text('请说出你想学的操作，说完后点击"完成"'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('完成'),
            ),
          ],
        ),
      );

      // stop() returns the ACTUAL output path (platform may change extension)
      final actualPath = await _recorder.stop();
      setState(() => _isListening = false);

      if (shouldStop != true || !mounted) return;

      // Read from the actual path (stop() returns reliable path)
      final audioFile = File(actualPath ?? filePath);
      if (!await audioFile.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('录音文件未生成，请重试'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final bytes = await audioFile.readAsBytes();
      if (bytes.length < 400) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('录音太短（${bytes.length}字节），请说完整句话'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        audioFile.delete().ignore();
        return;
      }
      final base64Audio = base64Encode(bytes);

      final result = await widget.modelClient.transcribeAudio(
        audioBase64: base64Audio,
      );
      audioFile.delete().ignore();

      if (!mounted || result.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('未识别到语音，请说清楚一点再试'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      _textController.text = result;
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) _generate();
    } catch (e) {
      if (mounted) {
        setState(() => _isListening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('录音失败：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Voice input handled by _startVoice() above — uses native Android RecognizerIntent

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

  Future<void> _deleteCard(SkillCard card) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('删除卡片'),
        content: Text('确定要删除"${card.title}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.cardRepository.remove(card.id);
      await _loadCards();
    }
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
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text(
          '学手机',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
        ),
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        backgroundColor: const Color(0xFFF2F2F7),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: '从截图生成卡片',
            onPressed: _isGenerating ? null : () => _screenshotToCard(),
          ),
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: '旧版截图教程',
            onPressed: () => Navigator.of(context).pushNamed('/screenshot'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isGenerating) _buildProgressBar(),
          Expanded(
            child: _cards.isEmpty && !_isGenerating
                ? _buildEmptyState()
                : _buildCardGrid(),
          ),
          _buildInputBar(),
        ],
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
                        width: progress *
                            (MediaQuery.of(context).size.width - 40),
                        height: 4,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF007AFF),
                              const Color(0xFF007AFF)
                                  .withValues(alpha: 0.7),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF007AFF)
                                  .withValues(alpha: 0.3),
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

  // ── Empty state ────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 48,
                color: Color(0xFF007AFF),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '告诉我你想学什么',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '在下方输入你想学的手机操作\n比如"给孙子打视频"、"发微信语音"',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFF8E8E93),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Card grid ──────────────────────────────────────────────────

  Widget _buildCardGrid() {
    return RefreshIndicator(
      onRefresh: _loadCards,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        itemCount: _cards.length + (_isGenerating ? 1 : 0),
        itemBuilder: (context, index) {
          if (_isGenerating && index == 0) {
            return _buildGeneratingCard();
          }
          final cardIndex = _isGenerating ? index - 1 : index;
          return _buildCard(_cards[cardIndex]);
        },
      ),
    );
  }

  Widget _buildGeneratingCard() {
    return AnimatedBuilder(
      animation: _progressAnim,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF007AFF).withValues(alpha: 0.15),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Color(0xFF007AFF),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '${_generatingElapsed}s',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF007AFF),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '正在生成...',
                  style: TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(SkillCard card) {
    return GestureDetector(
      onTap: () => _openCard(card),
      onLongPress: () => _deleteCard(card),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.smartphone_rounded,
                  color: Color(0xFF007AFF),
                  size: 24,
                ),
              ),
              const Spacer(),
              Text(
                card.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1C1E),
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.touch_app, size: 13, color: Colors.grey.shade500),
                  const SizedBox(width: 3),
                  Text(
                    '${card.stepCount} 步',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const Spacer(),
                  if (card.timesPracticed > 0)
                    Text(
                      '练${card.timesPracticed}次',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Input bar ──────────────────────────────────────────────────

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _isGenerating ? Colors.grey.shade100 : Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: _isGenerating
                      ? const Color(0xFF007AFF).withValues(alpha: 0.4)
                      : _isListening
                          ? const Color(0xFF007AFF).withValues(alpha: 0.35)
                          : Colors.grey.withValues(alpha: 0.12),
                  width: (_isGenerating || _isListening) ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                enabled: !_isGenerating,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _generate(),
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: _isListening
                      ? '正在聆听，再次点击麦克风结束...'
                      : _isGenerating
                          ? '正在生成中...'
                          : '打字或点击麦克风说话...',
                  hintStyle: TextStyle(
                    color: _isListening
                        ? const Color(0xFF007AFF)
                        : Colors.grey.shade400,
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  suffixIcon: _textController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.send_rounded, size: 22),
                          color: const Color(0xFF007AFF),
                          onPressed: _isGenerating ? null : _generate,
                        )
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Voice button — one tap to start system voice dialog
          IconButton(
            onPressed: _isGenerating || _isListening ? null : _startVoice,
            icon: const Icon(Icons.mic, size: 24),
            style: IconButton.styleFrom(
              backgroundColor: _isListening
                  ? Colors.red
                  : const Color(0xFF007AFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
