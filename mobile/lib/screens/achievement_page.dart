import 'package:flutter/material.dart';

import '../data/card_repository.dart';
import '../models/skill_card.dart';
import 'ui_practice_page.dart';

class AchievementPage extends StatefulWidget {
  const AchievementPage({
    super.key,
    this.cardRepository = const CardRepository(),
  });

  final CardRepository cardRepository;

  @override
  State<AchievementPage> createState() => _AchievementPageState();
}

class _AchievementPageState extends State<AchievementPage> {
  static const _primary = Color(0xFFFF6B35);
  static const _background = Color(0xFFF9F8F6);
  static const _progressTrack = Color(0xFFD9E3F6);

  int _tabIndex = 0;
  List<SkillCard> _cards = [];

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  Future<void> _loadCards() async {
    final cards = await widget.cardRepository.loadAll();
    if (mounted) setState(() => _cards = cards);
  }

  Future<void> _openCard(SkillCard card) async {
    await widget.cardRepository.incrementPractice(card.id);
    if (!mounted) return;
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                const _FakeStatusBar(),
                _TopToolbar(onSettings: () {}, onNotifications: () {}),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 116),
                    children: [
                      const _GreetingSection(),
                      const _ProgressCard(),
                      _Tabs(
                        selectedIndex: _tabIndex,
                        onChanged: (index) => setState(() => _tabIndex = index),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _tabIndex == 0
                              ? _LearningRecords(
                                  key: const ValueKey('records'),
                                  cards: _cards,
                                  onOpenCard: _openCard,
                                )
                              : const _AchievementGrid(
                                  key: ValueKey('achievements'),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomNavigation(
                onHome: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FakeStatusBar extends StatelessWidget {
  const _FakeStatusBar();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '10:30',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
          Row(
            children: [
              Icon(
                Icons.signal_cellular_4_bar_rounded,
                size: 24,
                color: Colors.black,
              ),
              SizedBox(width: 8),
              Icon(Icons.wifi_rounded, size: 24, color: Colors.black),
              SizedBox(width: 8),
              RotatedBox(
                quarterTurns: 1,
                child: Icon(
                  Icons.battery_full_rounded,
                  size: 24,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopToolbar extends StatelessWidget {
  const _TopToolbar({required this.onNotifications, required this.onSettings});

  final VoidCallback onNotifications;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.black, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'A',
                  style: TextStyle(
                    color: _AchievementPageState._primary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                SizedBox(width: 2),
                Text(
                  'A+',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _RoundToolButton(
                icon: Icons.notifications_none_rounded,
                onTap: onNotifications,
              ),
              const SizedBox(width: 16),
              _RoundToolButton(
                icon: Icons.settings_outlined,
                onTap: onSettings,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundToolButton extends StatelessWidget {
  const _RoundToolButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(
          side: BorderSide(color: Colors.black, width: 2),
        ),
        elevation: 1,
        shadowColor: Colors.black12,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(icon, color: Colors.black, size: 30),
        ),
      ),
    );
  }
}

class _GreetingSection extends StatelessWidget {
  const _GreetingSection();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '阿姨，您真棒！',
                  style: TextStyle(
                    fontSize: 36,
                    height: 44 / 36,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
              ),
              Text('👋', style: TextStyle(fontSize: 40, height: 1)),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '2026年7月8日 · 星期二',
            style: TextStyle(
              fontSize: 22,
              height: 32 / 22,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.10),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '已获得 '),
                      TextSpan(
                        text: '12',
                        style: TextStyle(
                          color: _AchievementPageState._primary,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      TextSpan(text: ' 枚勋章'),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 20,
                    height: 28 / 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
              Icon(
                Icons.workspace_premium_rounded,
                color: _AchievementPageState._primary,
                size: 34,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 24,
              color: _AchievementPageState._progressTrack,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.75,
                child: Container(
                  decoration: BoxDecoration(
                    color: _AchievementPageState._primary,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: _AchievementPageState._primary.withValues(
                          alpha: 0.40,
                        ),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              '距离下一等级还需 3 次练习',
              style: TextStyle(
                fontSize: 18,
                height: 24 / 18,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.selectedIndex, required this.onChanged});

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.black.withValues(alpha: 0.10),
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          _TabButton(
            label: '学习记录',
            selected: selectedIndex == 0,
            onTap: () => onChanged(0),
          ),
          _TabButton(
            label: '我的成就',
            selected: selectedIndex == 1,
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _AchievementPageState._primary : Colors.black;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected
                    ? _AchievementPageState._primary
                    : Colors.transparent,
                width: 4,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 20,
              height: 28 / 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _LearningRecords extends StatelessWidget {
  const _LearningRecords({
    super.key,
    required this.cards,
    required this.onOpenCard,
  });

  final List<SkillCard> cards;
  final ValueChanged<SkillCard> onOpenCard;

  @override
  Widget build(BuildContext context) {
    final allCards = [...cards, ..._defaultHistoryCards];
    return Column(
      children: [
        for (final indexed in allCards.indexed) ...[
          _RecordCard.fromSkillCard(
            indexed.$2,
            index: indexed.$1,
            onTap: () => onOpenCard(indexed.$2),
          ),
          if (indexed.$1 != allCards.length - 1) const SizedBox(height: 16),
        ],
      ],
    );
  }

  static final List<SkillCard> _defaultHistoryCards = [
    SkillCard(
      id: 'default-video-call',
      title: '视频通话练习',
      html: _demoHtml('视频通话练习', ['打开微信', '找到联系人', '点击视频通话']),
      stepCount: 3,
      createdAt: DateTime(2026, 7, 6),
    ),
    SkillCard(
      id: 'default-moments',
      title: '如何发朋友圈',
      html: _demoHtml('如何发朋友圈', ['进入发现页', '打开朋友圈', '点击发布']),
      stepCount: 3,
      createdAt: DateTime(2026, 7, 5),
    ),
    SkillCard(
      id: 'default-scan-pay',
      title: '扫码支付技巧',
      html: _demoHtml('扫码支付技巧', ['打开扫一扫', '对准二维码', '确认付款']),
      stepCount: 3,
      createdAt: DateTime(2026, 7, 4),
    ),
  ];

  static String _demoHtml(String title, List<String> steps) {
    final buttons = steps.indexed.map((item) {
      final step = item.$1 + 1;
      final label = item.$2;
      final top = 150 + item.$1 * 120;
      return '''
        <button class="target" style="top:${top}px" onclick="onTargetClick($step)">
          <span class="badge">$step</span>$label
        </button>
      ''';
    }).join();

    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<style>
*{box-sizing:border-box}
body{margin:0;background:#f7f8fb;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#202124}
.phone{position:relative;width:100vw;min-height:620px;padding:28px 22px;background:linear-gradient(#fff,#f7f8fb)}
h1{margin:0 0 10px;font-size:26px;font-weight:900}
p{margin:0 0 28px;color:#6b7280;font-size:17px;font-weight:700}
.target{position:absolute;left:50%;transform:translateX(-50%);width:245px;height:72px;border:0;border-radius:22px;background:#0b84ff;color:white;font-size:24px;font-weight:900;box-shadow:0 8px 0 #0065c7,0 12px 22px rgba(0,0,0,.15)}
.target:active{transform:translate(-50%,4px);box-shadow:0 4px 0 #0065c7}
.badge{display:inline-flex;align-items:center;justify-content:center;width:34px;height:34px;margin-right:12px;border-radius:50%;background:rgba(255,255,255,.24)}
.hint{position:absolute;left:22px;right:22px;bottom:32px;padding:18px;border-radius:20px;background:#fff;border:2px solid #e5e7eb;font-size:18px;font-weight:800;color:#4b5563}
</style>
</head>
<body>
<div class="phone">
  <h1>$title</h1>
  <p>请按顺序点击蓝色按钮完成练习</p>
  $buttons
  <div class="hint">点对后会出现绿色反馈，点错会提示你重新找位置。</div>
</div>
<script>
function onTargetClick(step) {}
window.__setPracticeStep = function(step) {
  document.querySelectorAll('.target').forEach(function(el, i) {
    var active = i + 1 === step;
    el.style.opacity = active ? '1' : '.35';
    el.style.pointerEvents = active ? 'auto' : 'auto';
  });
};
window.__setPracticeStep(1);
</script>
</body>
</html>
''';
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.duration,
    required this.date,
    this.onTap,
  });

  factory _RecordCard.fromSkillCard(
    SkillCard card, {
    required int index,
    required VoidCallback onTap,
  }) {
    final palette = [
      (
        icon: Icons.smartphone_rounded,
        iconColor: _AchievementPageState._primary,
        iconBg: const Color(0x1AFF6B35),
      ),
      (
        icon: Icons.touch_app_rounded,
        iconColor: const Color(0xFF2E7D32),
        iconBg: const Color(0xFFE8F5E9),
      ),
      (
        icon: Icons.school_rounded,
        iconColor: const Color(0xFF1976D2),
        iconBg: const Color(0xFFE3F2FD),
      ),
    ];
    final style = palette[index % palette.length];
    return _RecordCard(
      icon: style.icon,
      iconColor: style.iconColor,
      iconBg: style.iconBg,
      title: card.title,
      duration: '${(card.stepCount * 3).clamp(6, 30)}分钟',
      date: _formatDate(card.createdAt),
      onTap: onTap,
    );
  }

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String duration;
  final String date;
  final VoidCallback? onTap;

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.10),
              width: 2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 42),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 24,
                        height: 34 / 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '学习时长: $duration',
                      style: const TextStyle(
                        fontSize: 18,
                        height: 24 / 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      '日期: $date',
                      style: const TextStyle(
                        fontSize: 18,
                        height: 24 / 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.black,
                size: 34,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AchievementGrid extends StatelessWidget {
  const _AchievementGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _BadgeCard(
          imageUrl:
              'https://lh3.googleusercontent.com/aida/AP1WRLv3RmaNE2MSwkWKWDRTHuQjFrPgzyxl3FwHos978bwqkHYNwX3Umuma8PcDWjTT21hUjQaTs3loJvgB_mpErmHjf92S9XdMCEhJxghI8-LpoiAl667mN4wQDg-YfbFLjGSs0WVdQFrG_Wm1TsJvS0Px1uY7MH6Ue1bOS5fZn-2nyP9t4iKOdaPcil_RwEhzYJ7pD4EEXxY3pQna9EMkd-G24ife68mNlZw-NhtDhQtphUVvyuc3QTpcHA',
          fallbackIcon: Icons.workspace_premium_rounded,
          title: '朋友圈达人',
          date: '2026-07-05',
        ),
        _BadgeCard(
          imageUrl:
              'https://lh3.googleusercontent.com/aida/AP1WRLt6gRNbEDdwURqxCK6baHA9y-izcuvVh7kG6Q9egybvhU7-3-SHaHfPV-skUIdUJYtLBQtFLnxjgnJvpnqsa3b3ZnYjfYfQNqI_SVeantY53uRH75QpmEm9s3EncDRVSxOeevtIbluGY9rOlDaYK8IoZNIQxoi_NXz1Mpl8WfOEpD_JJFj6QVgJzbJmLajdPhGj_po1UxloRgCeSHOTbhKBGRpLiMI57Qhi6oWo94tQw0Irr8QRJJLLiag',
          fallbackIcon: Icons.video_call_rounded,
          title: '视频通话专家',
          date: '2026-06-28',
        ),
        _BadgeCard(
          fallbackIcon: Icons.history_rounded,
          title: '更多荣誉',
          date: '查看全部',
        ),
      ],
    );
  }
}

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({
    this.imageUrl,
    required this.fallbackIcon,
    required this.title,
    required this.date,
  });

  final String? imageUrl;
  final IconData fallbackIcon;
  final String title;
  final String date;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 56) / 2,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.10),
            width: 2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFFBEB),
                boxShadow: [
                  BoxShadow(
                    color: _AchievementPageState._primary.withValues(
                      alpha: 0.20,
                    ),
                    blurRadius: 10,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: imageUrl == null
                  ? Icon(
                      fallbackIcon,
                      size: 64,
                      color: _AchievementPageState._primary,
                    )
                  : Image.network(
                      imageUrl!,
                      width: 112,
                      height: 112,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(
                        fallbackIcon,
                        size: 64,
                        color: _AchievementPageState._primary,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                height: 32 / 22,
                fontWeight: FontWeight.w900,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              date,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                height: 24 / 18,
                fontWeight: FontWeight.w900,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({required this.onHome});

  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        32,
        12,
        32,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        border: Border(
          top: BorderSide(
            color: Colors.black.withValues(alpha: 0.10),
            width: 2,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _BottomNavItem(
            icon: Icons.home_outlined,
            label: '首页',
            active: false,
            onTap: onHome,
          ),
          const _BottomNavItem(
            icon: Icons.military_tech_rounded,
            label: '成就',
            active: true,
          ),
          const _BottomNavItem(
            icon: Icons.person_outline_rounded,
            label: '我的',
            active: false,
          ),
        ],
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? _AchievementPageState._primary : Colors.black;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
