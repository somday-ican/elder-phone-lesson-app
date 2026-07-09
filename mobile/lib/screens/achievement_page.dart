import 'package:flutter/material.dart';

class AchievementPage extends StatelessWidget {
  const AchievementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: const Color(0xFFF9F8F6),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('我的成就', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.black, letterSpacing: -0.5)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_outlined, size: 28),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            // Trophy
            const SizedBox(height: 20),
            const Text('🏆', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            const Text('完成了！', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.black)),
            const SizedBox(height: 6),
            const Text('你学会「给孙子打视频」了', style: TextStyle(fontSize: 16, color: Color(0xFF999999), fontWeight: FontWeight.w600)),
            const SizedBox(height: 32),
            // Achievement cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  _AchievementCard(icon: Icons.check_circle, color: const Color(0xFFFF6B35), value: '5/5', label: '完成步骤'),
                  const SizedBox(height: 12),
                  _AchievementCard(icon: Icons.speed, color: const Color(0xFFFF6B35), value: '92%', label: '准确率'),
                  const SizedBox(height: 12),
                  _AchievementCard(icon: Icons.timer_outlined, color: const Color(0xFFFF6B35), value: '2分30秒', label: '学习用时'),
                ],
              ),
            ),
            const Spacer(),
            // Bottom nav — same style as HomePage
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200, width: 0.5)),
              ),
              padding: EdgeInsets.only(bottom: bottom),
              height: 56 + bottom,
              child: Row(
                children: [
                  _AchievementNavItem(
                    icon: Icons.home_rounded, label: '首页', active: false,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  _AchievementNavItem(
                    icon: Icons.emoji_events_rounded, label: '成就', active: true,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.icon, required this.color, required this.value, required this.label});
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 16, color: Color(0xFF666666), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AchievementNavItem extends StatelessWidget {
  const _AchievementNavItem({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 28, color: active ? const Color(0xFFFF6B35) : Colors.grey),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? const Color(0xFFFF6B35) : Colors.grey)),
        ]),
      ),
    );
  }
}
