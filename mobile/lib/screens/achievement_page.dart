import 'package:flutter/material.dart';

class AchievementPage extends StatelessWidget {
  const AchievementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: const Color(0xFFF9F8F6),
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              // Status bar area
              const SizedBox(height: 8),
              // Header row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('我的成就', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.black, letterSpacing: -0.5)),
                    IconButton(icon: const Icon(Icons.share_outlined, size: 24, color: Colors.black), onPressed: () {}),
                  ],
                ),
              ),
              const Spacer(),
              // Trophy with glow
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: const Color(0xFFFF6B35).withValues(alpha: 0.15), blurRadius: 24, spreadRadius: 2)],
                ),
                child: const Text('🏆', style: TextStyle(fontSize: 72)),
              ),
              const SizedBox(height: 20),
              const Text('太好了！', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.black, letterSpacing: -0.5)),
              const SizedBox(height: 8),
              Text('你学会了「给孙子打视频」', style: TextStyle(fontSize: 18, color: Colors.black.withValues(alpha: 0.55), fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('这个新技能！', style: TextStyle(fontSize: 18, color: Colors.black.withValues(alpha: 0.55), fontWeight: FontWeight.w600)),
              const Spacer(),
              // Achievement cards — Figma style
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _AchievementCard(icon: Icons.check_circle_outline, value: '7', unit: '个', label: '学过的技能', progress: null),
                    const SizedBox(height: 12),
                    _AchievementCard(icon: Icons.star_outline, value: '5', unit: '个', label: '掌握的技能', progress: 5 / 7),
                    const SizedBox(height: 12),
                    _AchievementCard(icon: Icons.trending_up, value: '92', unit: '%', label: '操作准确率', progress: 0.92),
                  ],
                ),
              ),
              const Spacer(),
              // Bottom nav
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, -2))],
                ),
                padding: EdgeInsets.only(bottom: bottom),
                height: 56 + bottom,
                child: Row(
                  children: [
                    _NavItem(icon: Icons.home_rounded, label: '首页', active: false,
                      onTap: () => Navigator.of(context).pop()),
                    _NavItem(icon: Icons.emoji_events_rounded, label: '成就', active: true,
                      onTap: () {}),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.icon, required this.value, required this.unit, required this.label, this.progress});
  final IconData icon;
  final String value;
  final String unit;
  final String label;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: const Color(0xFFFF6B35).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: const Color(0xFFFF6B35), size: 24),
          ),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black.withValues(alpha: 0.8))),
          if (progress != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFFF6B35).withValues(alpha: 0.12),
                  color: const Color(0xFFFF6B35),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFFFF6B35))),
          const SizedBox(width: 2),
          Text(unit, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFFFF6B35).withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.active, required this.onTap});
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
