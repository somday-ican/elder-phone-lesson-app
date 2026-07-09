import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  String? _feedbackText;
  Color? _feedbackColor;
  bool _pageLoaded = false;
  bool _processingTap = false;

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
    // Inject step control so Flutter, not model-generated HTML, owns progress.
    // Generated pages only need onclick="onTargetClick(N)" targets.
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
  var _lastTargetClick = 0;
  var _activeStep = 1;
  var _targets = [];

  function stepFromAttr(attr) {
    if (!attr) return 0;
    var match = String(attr).match(/onTargetClick\\s*\\(\\s*(\\d+)\\s*\\)/);
    return match ? parseInt(match[1], 10) : 0;
  }

  function collectTargets() {
    _targets = Array.prototype.slice.call(document.querySelectorAll('[onclick]'))
      .map(function(el) {
        var step = stepFromAttr(el.getAttribute('onclick'));
        if (!step) return null;
        el.setAttribute('data-practice-target', 'true');
        el.setAttribute('data-practice-step', String(step));
        return { el: el, step: step };
      })
      .filter(Boolean);
    applyStep();
  }

  function applyStep() {
    _targets.forEach(function(item) {
      var active = item.step === _activeStep;
      item.el.setAttribute('data-step-active', active ? 'true' : 'false');
      item.el.setAttribute('data-step-inactive', active ? 'false' : 'true');
      item.el.setAttribute('aria-disabled', active ? 'false' : 'true');
    });
    var activeTarget = _targets.filter(function(item){ return item.step === _activeStep; })[0];
    if (activeTarget && activeTarget.el.scrollIntoView) {
      activeTarget.el.scrollIntoView({block:'center', inline:'nearest', behavior:'smooth'});
    }
  }

  window.__setPracticeStep = function(step) {
    _activeStep = Number(step) || 1;
    if (!_targets.length) collectTargets();
    applyStep();
  };

  window.onTargetClick = function(step) {
    var now = Date.now();
    if (now - _lastTargetClick < 250) return;
    _lastTargetClick = now;
    if (window.TargetBridge) {
      window.TargetBridge.postMessage(JSON.stringify({event:'target_click',stepIndex:Number(step) || 0}));
    }
  };

  function targetInfo(el) {
    while (el && el !== document.body) {
      if (el.getAttribute) {
        var step = Number(el.getAttribute('data-practice-step')) || stepFromAttr(el.getAttribute('onclick'));
        if (step) return { el: el, step: step };
      }
      el = el.parentElement;
    }
    return null;
  }

  document.addEventListener('click', function(e) {
    var info = targetInfo(e.target);
    if (info) {
      e.preventDefault();
      e.stopPropagation();
      window.onTargetClick(info.step);
      return;
    }
    if (Date.now() - _lastTargetClick > 300) {
      if (window.TargetBridge) {
        window.TargetBridge.postMessage(JSON.stringify({event: "wrong_click"}));
      }
    }
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
      await _controller.runJavaScript('window.__setPracticeStep($_currentStep);');
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
    if (_processingTap) return;
    _processingTap = true;

    if (step == _currentStep) {
      setState(() {
        _correctCount++;
        _feedbackText = '✓ 正确！';
        _feedbackColor = Colors.green;
      });

      if (_currentStep >= widget.targetCount) {
        Future.delayed(const Duration(seconds: 1), () {
          _processingTap = false;
          _showCompletion();
        });
      } else {
        Future.delayed(const Duration(milliseconds: 800), () {
          _processingTap = false;
          if (mounted) {
            setState(() {
              _currentStep++;
              _feedbackText = null;
              _feedbackColor = null;
            });
            _syncWebStep();
          }
        });
      }
    } else {
      _processingTap = false;
      _onWrongClick();
    }
  }

  void _onWrongClick() {
    // Skip wrong-click feedback if we just got a correct answer
    // (prevents concurrent correct+wrong feedback from JS race)
    if (_feedbackText != null && _feedbackColor == Colors.green) return;

    setState(() {
      _wrongCount++;
      _feedbackText = '✗ 点错了，请找到正确的按钮再试一次';
      _feedbackColor = Colors.red;
    });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _feedbackText = null;
          _feedbackColor = null;
        });
      }
    });
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
              _wrongCount == 0
                  ? '太棒了！全部点对了！🎉'
                  : '继续加油！💪',
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        title: Text(
          widget.title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MiniChip(icon: Icons.check, value: _correctCount, color: Colors.green),
                const SizedBox(width: 6),
                _MiniChip(icon: Icons.close, value: _wrongCount, color: Colors.red),
              ],
            ),
          ),
        ],
      ),
      body: Column(
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
                            ? Colors.green
                            : i == _currentStep
                                ? const Color(0xFF007AFF)
                                : Colors.white.withValues(alpha: 0.2),
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
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ),
          // Loading spinner while page loads
          if (!_pageLoaded)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          // WebView
          Expanded(
            child: Opacity(
              opacity: _pageLoaded ? 1.0 : 0.0,
              child: WebViewWidget(controller: _controller),
            ),
          ),
          // Feedback bar
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            child: _feedbackText != null
                ? Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: (_feedbackColor ?? Colors.grey)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _feedbackText!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _feedbackColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : const SizedBox(height: 8),
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
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 3),
          Text('$value',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 13)),
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
        Text('$value 次',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}
