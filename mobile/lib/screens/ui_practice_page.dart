import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

enum _PracticeFeedbackKind { correct, wrong }

class UIPracticePage extends StatefulWidget {
  const UIPracticePage({
    super.key,
    required this.html,
    required this.title,
    required this.targetCount,
  });

  final String html;
  final String title;
  final int targetCount;

  @override
  State<UIPracticePage> createState() => _UIPracticePageState();
}

class _UIPracticePageState extends State<UIPracticePage> {
  late WebViewController _controller;
  int _currentStep = 1;
  int _correctCount = 0;
  int _wrongCount = 0;
  _PracticeFeedbackKind? _feedbackKind;
  bool _pageLoaded = false;
  bool _processingTap = false;
  DateTime? _lastTargetClickAt;
  Timer? _pendingWrongFeedbackTimer;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            setState(() => _pageLoaded = true);
            _syncWebStep();
          },
        ),
      )
      ..addJavaScriptChannel(
        'TargetBridge',
        onMessageReceived: _handleJsMessage,
      )
      ..loadHtmlString(_wrapHtml(widget.html));
  }

  String _wrapHtml(String original) {
    // Inject CSS + click handler. The AI-generated HTML already has its own
    // onTargetClick() that handles page switching. We wrap it to add Flutter
    // bridge messaging and step validation — never overwrite it.
    final injectedScript = '''
<style>
html,body{width:100%!important;max-width:100%!important;overflow-x:hidden!important;}
body{margin:0!important;-webkit-text-size-adjust:100%!important;}
.phone{width:min(375px,100vw)!important;max-width:100vw!important;margin-left:auto!important;margin-right:auto!important;}
[data-practice-target]{transition:opacity .18s ease,filter .18s ease,transform .18s ease;}
[data-practice-target][data-step-inactive="true"]{opacity:.32!important;filter:grayscale(.25)!important;animation:none!important;}
[data-practice-target][data-step-active="true"]{outline:3px solid rgba(0,122,255,.35)!important;outline-offset:2px!important;}
</style>
<script>
(function(){
  var _lastClick = 0;
  var _lastPointerWasTarget = false;

  function findTargetElement(start) {
    var el = start;
    while (el && el !== document.body) {
      var oc = (el.getAttribute && el.getAttribute('onclick')) || '';
      var practiceTarget = el.getAttribute && el.getAttribute('data-practice-target') === 'true';
      if (practiceTarget || oc.indexOf('onTargetClick') !== -1) return el;
      el = el.parentElement;
    }
    return null;
  }

  // Wrap the AI-generated onTargetClick (which handles page switching)
  // with Flutter bridge messaging. Never overwrite it.
  var _aiHandler = window.onTargetClick;
  if (typeof _aiHandler === 'function') {
    window._aiOnTargetClick = _aiHandler;
  }
  window.onTargetClick = function(step) {
    var now = Date.now();
    if (now - _lastClick < 300) return;
    _lastClick = now;
    // Notify Flutter
    if (window.TargetBridge) {
      window.TargetBridge.postMessage(JSON.stringify({event:'target_click',stepIndex:Number(step)||1}));
    }
  };

  // Track which target buttons exist
  function collectTargets() {
    var all = document.querySelectorAll('[onclick*="onTargetClick"]');
    all.forEach(function(el, i) {
      el.setAttribute('data-practice-target', 'true');
      el.setAttribute('data-practice-step', String(i + 1));
    });
  }

  function rememberPointer(e) {
    _lastPointerWasTarget = !!findTargetElement(e.target);
    if (!_lastPointerWasTarget) {
      setTimeout(function(){ _lastPointerWasTarget = false; }, 450);
    }
  }
  document.addEventListener('pointerdown', rememberPointer, true);
  document.addEventListener('touchstart', rememberPointer, true);

  // Click handler: detect clicks on non-target areas
  document.addEventListener('click', function(e) {
    if (_lastPointerWasTarget || findTargetElement(e.target)) {
      _lastPointerWasTarget = false;
      return;
    }

    // Defer wrong-click reporting until target onclick handlers have had a
    // chance to update _lastClick. This prevents a brief wrong panel flash on
    // valid taps in nested/generated HTML.
    setTimeout(function() {
      if (Date.now() - _lastClick > 180) {
        if (window.TargetBridge) {
          window.TargetBridge.postMessage(JSON.stringify({event:'wrong_click'}));
        }
      }
    }, 0);
  }, true);

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', collectTargets);
  } else {
    collectTargets();
  }
})();
</script>
</body>''';

    return original
        .replaceFirst(
          '</head>',
          '<meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=no"></head>',
        )
        .replaceFirst('</body>', injectedScript);
  }

  Future<void> _syncWebStep() async {
    if (!_pageLoaded) return;
    try {
      await _controller.runJavaScript(
        'window.__setPracticeStep($_currentStep);',
      );
    } catch (_) {
      // WebView may still be settling; the injected script also initializes itself.
    }
  }

  void _handleJsMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final event = data['event'] as String?;

      switch (event) {
        case 'target_click':
          final step = (data['stepIndex'] as num?)?.toInt() ?? 0;
          _onTargetClick(step);
        case 'wrong_click':
          _onWrongClick();
      }
    } catch (_) {}
  }

  void _onTargetClick(int step) {
    // Guard: ignore taps while processing (prevents double-tap skip)
    if (_pendingWrongFeedbackTimer != null) {
      _pendingWrongFeedbackTimer?.cancel();
      _pendingWrongFeedbackTimer = null;
      _processingTap = false;
    } else if (_processingTap) {
      return;
    }
    _lastTargetClickAt = DateTime.now();
    _processingTap = true;

    if (step == _currentStep) {
      setState(() {
        _correctCount++;
        _feedbackKind = _PracticeFeedbackKind.correct;
      });
      _playCorrectFeedback();
    } else {
      _processingTap = false;
      _onWrongClick();
    }
  }

  void _onWrongClick() {
    final lastTargetClickAt = _lastTargetClickAt;
    if (lastTargetClickAt != null &&
        DateTime.now().difference(lastTargetClickAt).inMilliseconds < 700) {
      return;
    }
    if (_processingTap ||
        _feedbackKind != null ||
        _pendingWrongFeedbackTimer != null) {
      return;
    }

    _processingTap = true;
    _pendingWrongFeedbackTimer = Timer(const Duration(milliseconds: 120), () {
      _pendingWrongFeedbackTimer = null;
      if (!mounted || _feedbackKind != null) {
        _processingTap = false;
        return;
      }
      setState(() {
        _wrongCount++;
        _feedbackKind = _PracticeFeedbackKind.wrong;
      });
      _playWrongFeedback();
    });
  }

  Future<void> _playCorrectFeedback() async {
    HapticFeedback.mediumImpact();
    await SystemSound.play(SystemSoundType.click);
  }

  Future<void> _playWrongFeedback() async {
    HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    HapticFeedback.mediumImpact();
    await SystemSound.play(SystemSoundType.alert);
  }

  Future<void> _continueAfterCorrect() async {
    final completed = _currentStep >= widget.targetCount;
    try {
      await _controller.runJavaScript(
        'if(window._aiOnTargetClick){window._aiOnTargetClick($_currentStep);}',
      );
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _feedbackKind = null;
      _processingTap = false;
      if (!completed) {
        _currentStep++;
      }
    });

    if (completed) {
      _showCompletion();
    } else {
      _syncWebStep();
    }
  }

  void _dismissWrongFeedback() {
    setState(() {
      _feedbackKind = null;
      _processingTap = false;
    });
  }

  @override
  void dispose() {
    _pendingWrongFeedbackTimer?.cancel();
    super.dispose();
  }

  void _showCompletion() {
    if (!mounted) return;
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
              _wrongCount == 0 ? '太棒了！全部点对了！🎉' : '继续加油！💪',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop(); // close dialog
              Navigator.of(context).pop(); // go back
            },
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F8F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF9F8F6),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.black,
            size: 22,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
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
      body: Stack(
        children: [
          Column(
            children: [
              // Progress bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
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
                                ? const Color(0xFF58CC02)
                                : i == _currentStep
                                ? const Color(0xFF1CB0F6)
                                : const Color(0xFFE5E5E5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Step indicator
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                child: Text(
                  '第 $_currentStep 步 / 共 ${widget.targetCount} 步',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ),
              // Loading spinner while page loads
              if (!_pageLoaded)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF58CC02)),
                  ),
                ),
              // WebView
              Expanded(
                child: Opacity(
                  opacity: _pageLoaded ? 1.0 : 0.0,
                  child: WebViewWidget(controller: _controller),
                ),
              ),
            ],
          ),
          _DuolingoFeedbackPanel(
            kind: _feedbackKind,
            onContinue: _continueAfterCorrect,
            onDismissWrong: _dismissWrongFeedback,
          ),
        ],
      ),
    );
  }
}

class _DuolingoFeedbackPanel extends StatelessWidget {
  const _DuolingoFeedbackPanel({
    required this.kind,
    required this.onContinue,
    required this.onDismissWrong,
  });

  final _PracticeFeedbackKind? kind;
  final VoidCallback onContinue;
  final VoidCallback onDismissWrong;

  static const _green = Color(0xFF58CC02);
  static const _greenDark = Color(0xFF46A302);
  static const _greenBg = Color(0xFFD7FFB8);
  static const _red = Color(0xFFFF4B4B);
  static const _redDark = Color(0xFFE53838);
  static const _redBg = Color(0xFFFFDFE0);

  @override
  Widget build(BuildContext context) {
    final visible = kind != null;
    final correct = kind == _PracticeFeedbackKind.correct;
    final baseColor = correct ? _green : _red;
    final shadowColor = correct ? _greenDark : _redDark;
    final bgColor = correct ? _greenBg : _redBg;
    final title = correct ? '真厉害！' : '不正确';
    final buttonText = correct ? '继续' : '知道了';

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
          offset: visible ? Offset.zero : const Offset(0, 1.05),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: visible ? 1 : 0,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                20,
                22,
                20,
                MediaQuery.of(context).padding.bottom + 18,
              ),
              decoration: BoxDecoration(
                color: bgColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: baseColor,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          correct ? Icons.check_rounded : Icons.close_rounded,
                          color: Colors.white,
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: correct ? _greenDark : _redDark,
                            fontSize: 32,
                            height: 1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: Icon(
                          Icons.ios_share_rounded,
                          color: correct ? _greenDark : _redDark,
                          size: 30,
                        ),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: Icon(
                          Icons.flag_outlined,
                          color: correct ? _greenDark : _redDark,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                  if (!correct) ...[
                    const SizedBox(height: 18),
                    Text(
                      '请点击屏幕上蓝色高亮的正确位置',
                      style: TextStyle(
                        color: _redDark,
                        fontSize: 22,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: _BouncyFeedbackButton(
                      color: baseColor,
                      shadowColor: shadowColor,
                      onPressed: correct ? onContinue : onDismissWrong,
                      child: Text(
                        buttonText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BouncyFeedbackButton extends StatefulWidget {
  const _BouncyFeedbackButton({
    required this.color,
    required this.shadowColor,
    required this.onPressed,
    required this.child,
  });

  final Color color;
  final Color shadowColor;
  final VoidCallback onPressed;
  final Widget child;

  @override
  State<_BouncyFeedbackButton> createState() => _BouncyFeedbackButtonState();
}

class _BouncyFeedbackButtonState extends State<_BouncyFeedbackButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onPressed();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _pressed ? 5 : 0, 0),
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: widget.shadowColor,
              blurRadius: 0,
              offset: Offset(0, _pressed ? 2 : 7),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: widget.child,
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
        color: color.withValues(alpha: 0.15),
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
