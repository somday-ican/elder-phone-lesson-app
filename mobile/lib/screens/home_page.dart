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

const _primary = Color(0xFFFF6B35);
const _bg = Color(0xFFFFF8F0);

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.modelClient, this.cardRepository = const CardRepository()});
  final ModelClient modelClient;
  final CardRepository cardRepository;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  final _textCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final AudioRecorder _recorder = AudioRecorder();
  bool _listening = false;
  bool _generating = false;
  List<SkillCard> _cards = [];
  int _elapsed = 0;
  Timer? _timer;
  late AnimationController _pCtrl;
  late Animation<double> _pAnim;

  @override
  void initState() {
    super.initState();
    _pCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 80));
    _pAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.15), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.15, end: 0.45), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.45, end: 0.75), weight: 3),
      TweenSequenceItem(tween: Tween(begin: 0.75, end: 0.90), weight: 4),
    ]).animate(_pCtrl);
    _loadCards();
  }

  Future<void> _loadCards() async {
    final c = await widget.cardRepository.loadAll();
    if (mounted) setState(() => _cards = c);
  }

  // ── Generate ──────────────────────────────────────────────────

  Future<void> _generate() async {
    final g = _textCtrl.text.trim();
    if (g.isEmpty || _generating) return;
    _focusNode.unfocus();
    setState(() { _generating = true; _elapsed = 0; });
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _pCtrl.forward(from: 0); });
    _timer?.cancel(); _timer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _elapsed++); });
    try {
      final r = await widget.modelClient.chatGenerate(goal: g);
      _timer?.cancel(); if (!mounted) return;
      final card = SkillCard.create(title: r.title, html: r.html, stepCount: r.steps.length);
      await widget.cardRepository.add(card); await _loadCards(); _textCtrl.clear();
      _pCtrl.stop(); setState(() => _generating = false);
      _openCard(card);
    } catch (e) {
      _timer?.cancel(); _pCtrl.stop();
      if (mounted) { setState(() => _generating = false); _snack('生成失败：$e'); }
    }
  }

  // ── Voice ──────────────────────────────────────────────────────

  Future<void> _startVoice() async {
    if (_listening || _generating) return;
    if (!await _recorder.hasPermission()) { _snack('需要麦克风权限'); return; }
    setState(() => _listening = true);
    try {
      final fp = '${Directory.systemTemp.path}/voice_input.m4a';
      final aac = await _recorder.isEncoderSupported(AudioEncoder.aacLc);
      await _recorder.start(RecordConfig(encoder: aac ? AudioEncoder.aacLc : AudioEncoder.aacHe, sampleRate: 16000, numChannels: 1, bitRate: aac ? 64000 : 32000), path: fp);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) { await _recorder.stop(); return; }
      final ok = await showDialog<bool>(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(children: [Icon(Icons.mic, color: Colors.red, size: 28), SizedBox(width: 10), Text('正在聆听…', style: TextStyle(fontWeight: FontWeight.w800))]),
        content: const Text('请说你想学的操作，说完点完成', style: TextStyle(fontSize: 20)),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: _primary), child: const Text('完成'))],
      ));
      final path = await _recorder.stop();
      setState(() => _listening = false);
      if (ok != true || !mounted) return;
      final f = File(path ?? fp); if (!await f.exists()) { _snack('录音文件未生成'); return; }
      final b = await f.readAsBytes();
      if (b.length < 400) { _snack('录音太短'); f.delete().ignore(); return; }
      final t = await widget.modelClient.transcribeAudio(audioBase64: base64Encode(b));
      f.delete().ignore();
      if (!mounted || t.isEmpty) { _snack('未识别到语音'); return; }
      _textCtrl.text = t;
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) _generate();
    } catch (e) { if (mounted) { setState(() => _listening = false); _snack('录音失败：$e'); } }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m, style: const TextStyle(fontSize: 18)), behavior: SnackBarBehavior.floating, backgroundColor: Colors.red.shade700));
  }

  // ── Card actions ───────────────────────────────────────────────

  void _openCard(SkillCard c) {
    widget.cardRepository.incrementPractice(c.id);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => UIPracticePage(html: c.html, title: c.title, targetCount: c.stepCount)));
  }

  Future<void> _deleteCard(SkillCard c) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('删除卡片', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Text('确定删除「${c.title}」？', style: const TextStyle(fontSize: 20)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('删除'))],
    ));
    if (ok == true) { await widget.cardRepository.remove(c.id); await _loadCards(); }
  }

  Future<void> _screenshotToCard() async {
    if (_generating || _listening) return;
    final files = await ImagePicker().pickMultiImage(imageQuality: 50);
    if (files.isEmpty) return;
    final gc = TextEditingController();
    final goal = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('这些截图是做什么的？', style: TextStyle(fontWeight: FontWeight.w800)),
      content: TextField(controller: gc, autofocus: true, decoration: const InputDecoration(hintText: '比如：我要给孙子打微信视频')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, gc.text.trim()), style: FilledButton.styleFrom(backgroundColor: _primary), child: const Text('生成'))],
    ));
    gc.dispose();
    if (!mounted || goal == null || goal.isEmpty) return;
    final g = goal;
    setState(() { _generating = true; _elapsed = 0; });
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _pCtrl.forward(from: 0); });
    _timer?.cancel(); _timer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _elapsed++); });
    try {
      final b64 = <String>[];
      for (final f in files) {
        final b = await File(f.path).readAsBytes();
        final d = img.decodeImage(b);
        if (d != null) {
          const mw = 270;
          final rs = d.width > mw ? img.copyResize(d, width: mw, height: (d.height * mw / d.width).round()) : d;
          b64.add('data:image/jpeg;base64,${base64Encode(img.encodeJpg(rs, quality: 50))}');
        } else { b64.add('data:image/jpeg;base64,${base64Encode(b)}'); }
      }
      final r = await widget.modelClient.chatGenerate(goal: g, screenshotBase64s: b64);
      _timer?.cancel();
      if (!mounted) return;
      final c = SkillCard.create(title: r.title, html: r.html, stepCount: r.steps.length);
      await widget.cardRepository.add(c); await _loadCards();
      _pCtrl.stop(); setState(() => _generating = false);
      _openCard(c);
    } catch (e) { _timer?.cancel(); _pCtrl.stop(); if (mounted) { setState(() => _generating = false); _snack('生成失败：$e'); } }
  }

  @override
  void dispose() { _textCtrl.dispose(); _focusNode.dispose(); _timer?.cancel(); _pCtrl.dispose(); super.dispose(); }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(bottom: false, child: Column(children: [
        // Hero header — Codex design
        Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          width: double.infinity,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('阿姨，早上好 👋', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.black)),
            const SizedBox(height: 4),
            const Text('今天想学什么？', style: TextStyle(fontSize: 17, color: Color(0xFF999999), fontWeight: FontWeight.w500)),
          ]),
        ),
        if (_generating) _ProgressBar(elapsed: _elapsed, anim: _pAnim),
        Expanded(
          child: _cards.isEmpty && !_generating
              ? Center(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    GestureDetector(
                      onTap: _startVoice,
                      child: Container(
                        width: 140, height: 140,
                        decoration: BoxDecoration(color: _primary.withValues(alpha: 0.08), shape: BoxShape.circle),
                        child: Center(
                          child: Container(
                            width: 80, height: 80,
                            decoration: const BoxDecoration(color: _primary, shape: BoxShape.circle),
                            child: const Icon(Icons.mic, color: Colors.white, size: 40),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('点击说话', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _primary)),
                    const SizedBox(height: 8),
                    const Text('或输入你想学的操作', style: TextStyle(fontSize: 16, color: Color(0xFF999999))),
                  ]),
                ))
              : _CardGrid(cards: _cards, generating: _generating, elapsed: _elapsed, onOpen: _openCard, onDelete: _deleteCard, onVoice: _startVoice),
        ),
        if (_cards.isNotEmpty && !_generating)
          _VoiceBar(ctrl: _textCtrl, focus: _focusNode, listening: _listening, generating: _generating, onSend: _generate, onVoice: _startVoice, onPhoto: _screenshotToCard),
        const _BottomNav(current: 0),
      ])),
    );
  }
}

// ── Progress Bar ─────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.elapsed, required this.anim});
  final int elapsed;
  final Animation<double> anim;
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: anim, builder: (ctx, _) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: _primary.withValues(alpha: 0.1), blurRadius: 8)]),
        child: Column(children: [
          Row(children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _primary)),
            const SizedBox(width: 10),
            Text('AI 正在生成教程…', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primary)),
            const Spacer(), Text('${elapsed}s', style: TextStyle(fontSize: 13, color: _primary.withValues(alpha: 0.6))),
          ]),
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: anim.value, minHeight: 3, backgroundColor: _primary.withValues(alpha: 0.08), color: _primary)),
        ]),
      );
    });
  }
}

// ── Card Grid ────────────────────────────────────────────────────

class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.cards, required this.generating, required this.elapsed, required this.onOpen, required this.onDelete, required this.onVoice});
  final List<SkillCard> cards;
  final bool generating;
  final int elapsed;
  final ValueChanged<SkillCard> onOpen;
  final ValueChanged<SkillCard> onDelete;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.82),
      itemCount: cards.length + (generating ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (generating && i == 0) return _GeningCard(elapsed: elapsed);
        final ci = generating ? i - 1 : i;
        final c = cards[ci];
        return GestureDetector(
          onTap: () => onOpen(c), onLongPress: () => onDelete(c),
          child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)]),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 44, height: 44, decoration: BoxDecoration(color: _primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.smartphone_rounded, color: _primary, size: 24)),
                const Spacer(),
                Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.touch_app, size: 13, color: Colors.grey.shade500), const SizedBox(width: 3),
                  Text('${c.stepCount} 步', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  const Spacer(),
                  if (c.timesPracticed > 0) Text('练${c.timesPracticed}次', style: TextStyle(fontSize: 11, color: Colors.green.shade600, fontWeight: FontWeight.w600)),
                ]),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _GeningCard extends StatelessWidget {
  const _GeningCard({required this.elapsed});
  final int elapsed;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: _primary.withValues(alpha: 0.2), width: 2)),
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3, color: _primary)),
      const SizedBox(height: 16), Text('${elapsed}s', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: _primary)),
      const SizedBox(height: 4), const Text('正在生成…', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13)),
    ])),
  );
}

// ── Voice bar (bottom input when cards exist) ────────────────────

class _VoiceBar extends StatelessWidget {
  const _VoiceBar({required this.ctrl, required this.focus, required this.listening, required this.generating, required this.onSend, required this.onVoice, required this.onPhoto});
  final TextEditingController ctrl;
  final FocusNode focus;
  final bool listening, generating;
  final VoidCallback onSend, onVoice, onPhoto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: BoxDecoration(color: _bg, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, -2))]),
      child: Row(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: listening ? _primary.withValues(alpha: 0.5) : Colors.grey.withValues(alpha: 0.12), width: listening ? 2 : 1)),
            child: TextField(
              controller: ctrl, focusNode: focus, enabled: !generating, textInputAction: TextInputAction.send, onSubmitted: (_) => onSend(),
              style: const TextStyle(fontSize: 16), decoration: InputDecoration(
              hintText: listening ? '正在聆听…' : '打字或点麦克风说话…',
              hintStyle: TextStyle(fontSize: 14, color: listening ? _primary : Colors.grey.shade400),
              border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              suffixIcon: ctrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.send_rounded, size: 22), color: _primary, onPressed: generating ? null : onSend) : null,
            )),
          ),
        ),
        const SizedBox(width: 10),
        IconButton(onPressed: generating ? null : onVoice, icon: const Icon(Icons.mic, size: 24), style: IconButton.styleFrom(backgroundColor: listening ? Colors.red : _primary, foregroundColor: Colors.white, padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)))),
        const SizedBox(width: 6),
        IconButton(onPressed: generating ? null : onPhoto, icon: const Icon(Icons.add_photo_alternate_outlined, size: 24), style: IconButton.styleFrom(foregroundColor: _primary)),
      ]),
    );
  }
}

// ── Bottom Nav ───────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.current});
  final int current;
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, -2))]),
      height: 56 + bottom, padding: EdgeInsets.only(bottom: bottom),
      child: Row(children: [
        _NavTab(icon: Icons.home_rounded, label: '首页', active: current == 0, onTap: () {}),
        _NavTab(icon: Icons.emoji_events_rounded, label: '成就', active: false, onTap: () => Navigator.of(context).pushNamed('/achievements')),
      ]),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon; final String label; final bool active; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Expanded(child: GestureDetector(onTap: onTap, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 28, color: active ? _primary : Colors.grey),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? _primary : Colors.grey)),
    ])));
  }
}
