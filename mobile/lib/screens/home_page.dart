import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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

class _HomePageState extends State<HomePage> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  late stt.SpeechToText _speech;
  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isGenerating = false;
  List<SkillCard> _cards = [];

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _loadCards();
  }

  Future<void> _initSpeech() async {
    _speech = stt.SpeechToText();
    try {
      final available = await _speech.initialize(
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (_) {
          setState(() => _isListening = false);
        },
      );
      setState(() => _speechAvailable = available);
    } catch (_) {
      setState(() => _speechAvailable = false);
    }
  }

  Future<void> _loadCards() async {
    final cards = await widget.cardRepository.loadAll();
    if (mounted) setState(() => _cards = cards);
  }

  Future<void> _generate() async {
    final goal = _textController.text.trim();
    if (goal.isEmpty || _isGenerating) return;

    setState(() => _isGenerating = true);

    try {
      final result = await widget.modelClient.chatGenerate(goal: goal);
      if (!mounted) return;

      final card = SkillCard.create(
        title: result.title,
        html: result.html,
        stepCount: result.steps.length,
      );

      await widget.cardRepository.add(card);
      await _loadCards();
      _textController.clear();

      setState(() => _isGenerating = false);

      // Auto-open the new card for practice
      _openCard(card);
    } catch (error) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('生成失败：$error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) return;
    try {
      await _speech.listen(
        onResult: (result) {
          _textController.text = result.recognizedWords;
          if (result.finalResult) {
            setState(() => _isListening = false);
          }
        },
        // ignore: deprecated_member_use
        localeId: 'zh_CN',
      );
      setState(() => _isListening = true);
    } catch (_) {
      // Fallback to system default locale
      try {
        await _speech.listen(
          onResult: (result) {
            _textController.text = result.recognizedWords;
            if (result.finalResult) {
              setState(() => _isListening = false);
            }
          },
        );
        setState(() => _isListening = true);
      } catch (_) {
        setState(() => _isListening = false);
      }
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
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

  Future<void> _deleteCard(SkillCard card) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('删除卡片'),
        content: Text('确定要删除「${card.title}」吗？'),
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
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: '截图教程',
            onPressed: () {
              Navigator.of(context).pushNamed('/screenshot');
            },
          ),
        ],
      ),
      body: Column(
        children: [
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
              '告诉我想学什么',
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
          // Generating card placeholder
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF007AFF).withValues(alpha: 0.2),
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
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(height: 14),
            Text(
              '正在生成...',
              style: TextStyle(
                color: Color(0xFF007AFF),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
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
              // Icon
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
              // Title
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
              // Meta info
              Row(
                children: [
                  Icon(Icons.touch_app, size: 13, color: Colors.grey.shade500),
                  const SizedBox(width: 3),
                  Text(
                    '${card.stepCount} 步',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: _isGenerating
                      ? const Color(0xFF007AFF).withValues(alpha: 0.4)
                      : Colors.grey.withValues(alpha: 0.12),
                  width: _isGenerating ? 2 : 1,
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
                  hintText: _isListening ? '正在聆听...' : '打字或按住说话...',
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
                          onPressed:
                              _isGenerating ? null : _generate,
                        )
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Mic button
          GestureDetector(
            onLongPressStart: (_) => _startListening(),
            onLongPressEnd: (_) => _stopListening(),
            onTap: _speechAvailable ? _startListening : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _isListening
                    ? Colors.red
                    : _speechAvailable
                        ? const Color(0xFF007AFF)
                        : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(26),
                boxShadow: _isListening
                    ? [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.3),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                _isListening ? Icons.mic : Icons.mic_none,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
