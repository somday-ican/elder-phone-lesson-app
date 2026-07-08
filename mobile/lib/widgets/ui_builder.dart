import 'package:flutter/material.dart';

import '../models/ui_description.dart';

/// Renders a [UIWidget] tree as real Flutter widgets.
class UIBuilder extends StatelessWidget {
  const UIBuilder({
    super.key,
    required this.widget,
    this.interactive = false,
    this.currentStepIndex,
    this.onTargetTap,
  });

  final UIWidget widget;
  final bool interactive;
  final int? currentStepIndex;
  final ValueChanged<UIWidget>? onTargetTap;

  @override
  Widget build(BuildContext context) {
    return _buildWidget(context, widget);
  }

  Widget _buildWidget(BuildContext context, UIWidget w) {
    switch (w.type) {
      case 'column':
        return _buildColumn(context, w);
      case 'row':
        return _buildRow(context, w);
      case 'text':
        return _buildText(w);
      case 'button':
        return _buildButton(context, w);
      case 'outlinedButton':
        return _buildOutlinedButton(context, w);
      case 'listTile':
        return _buildListTile(context, w);
      case 'divider':
        return const Divider(height: 1, thickness: 0.5);
      case 'icon':
        return _buildIcon(w);
      case 'iconButton':
        return _buildIconButton(context, w);
      case 'card':
        return _buildCard(context, w);
      case 'switch':
        return _buildSwitch(w);
      case 'textField':
        return _buildTextField(w);
      case 'avatar':
        return _buildAvatar(w);
      case 'chip':
        return _buildChip(context, w);
      case 'appBar':
        return const SizedBox.shrink(); // handled by Scaffold
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Layout ────────────────────────────────────────────────────

  Widget _buildColumn(BuildContext context, UIWidget w) {
    final children = w.children ?? [];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children.map((c) => _buildWidget(context, c)).toList(),
      ),
    );
  }

  Widget _buildRow(BuildContext context, UIWidget w) {
    final children = w.children ?? [];
    return Row(
      children: children.map((c) => _buildWidget(context, c)).toList(),
    );
  }

  // ── Text ──────────────────────────────────────────────────────

  Widget _buildText(UIWidget w) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        w.content ?? w.label ?? '',
        style: TextStyle(
          fontSize: w.fontSize ?? 15,
          fontWeight: parseFontWeight(w.fontWeight),
          color: parseColor(w.color ?? '#1C1C1E'),
        ),
      ),
    );
  }

  // ── Buttons ───────────────────────────────────────────────────

  Widget _buildButton(BuildContext context, UIWidget w) {
    final isCurrentTarget = interactive &&
        w.isTarget &&
        w.stepIndex == currentStepIndex;

    final bgColor = parseColor(w.backgroundColor ?? '#007AFF');
    final fgColor = parseColor(w.textColor ?? '#FFFFFF');
    final radius = w.borderRadius ?? 12;

    Widget button = ElevatedButton(
      onPressed: (interactive && w.isTarget)
          ? () => onTargetTap?.call(w)
          : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        elevation: w.isTarget ? 2 : 0,
      ),
      child: Text(
        w.label ?? '按钮',
        style: TextStyle(
          fontSize: w.fontSize ?? 17,
          fontWeight: parseFontWeight(w.fontWeight ?? 'bold'),
        ),
      ),
    );

    // Pulse animation for current target
    if (isCurrentTarget) {
      button = _PulseWrapper(child: button);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(child: button),
    );
  }

  Widget _buildOutlinedButton(BuildContext context, UIWidget w) {
    final borderColor = parseColor(w.color ?? '#007AFF');
    final textColor = parseColor(w.textColor ?? w.color ?? '#007AFF');
    final radius = w.borderRadius ?? 12;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: OutlinedButton(
          onPressed: (interactive && w.isTarget)
              ? () => onTargetTap?.call(w)
              : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: textColor,
            side: BorderSide(color: borderColor, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
          child: Text(
            w.label ?? '按钮',
            style: TextStyle(
              fontSize: w.fontSize ?? 17,
              fontWeight: parseFontWeight(w.fontWeight ?? 'bold'),
            ),
          ),
        ),
      ),
    );
  }

  // ── ListTile ──────────────────────────────────────────────────

  Widget _buildListTile(BuildContext context, UIWidget w) {
    final isTarget = interactive && w.isTarget;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: isTarget
            ? [
                BoxShadow(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
        border: isTarget
            ? Border.all(
                color: const Color(0xFF007AFF).withValues(alpha: 0.5),
                width: 2,
              )
            : null,
      ),
      child: ListTile(
        leading: w.leading != null ? _buildWidget(context, w.leading!) : null,
        trailing:
            w.trailing != null ? _buildWidget(context, w.trailing!) : null,
        title: w.title != null
            ? Text(
                w.title!,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              )
            : null,
        subtitle: w.subtitle != null
            ? Text(
                w.subtitle!,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                ),
              )
            : null,
        onTap: (interactive && w.isTarget)
            ? () => onTargetTap?.call(w)
            : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Icons ─────────────────────────────────────────────────────

  Widget _buildIcon(UIWidget w) {
    return Icon(
      mapIcon(w.icon ?? 'circle'),
      color: parseColor(w.color ?? '#8E8E93'),
      size: w.fontSize ?? 24,
    );
  }

  Widget _buildIconButton(BuildContext context, UIWidget w) {
    return IconButton(
      onPressed: null,
      icon: Icon(
        mapIcon(w.icon ?? 'circle'),
        color: parseColor(w.color ?? '#007AFF'),
        size: w.fontSize ?? 24,
      ),
      tooltip: w.label,
    );
  }

  // ── Card ──────────────────────────────────────────────────────

  Widget _buildCard(BuildContext context, UIWidget w) {
    final children = w.children ?? [];
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: Colors.grey.withValues(alpha: 0.12),
        ),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children.map((c) => _buildWidget(context, c)).toList(),
        ),
      ),
    );
  }

  // ── Misc ──────────────────────────────────────────────────────

  Widget _buildSwitch(UIWidget w) {
    return Switch(
      value: w.value ?? false,
      onChanged: null, // non-interactive
    );
  }

  Widget _buildTextField(UIWidget w) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        decoration: InputDecoration(
          hintText: w.label ?? '请输入',
          filled: true,
          fillColor: Colors.grey.withValues(alpha: 0.08),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.all(14),
        ),
      ),
    );
  }

  Widget _buildAvatar(UIWidget w) {
    final radius = (w.width ?? 24) / 2;
    if (w.imageUrl != null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(w.imageUrl!),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: parseColor(w.backgroundColor ?? '#007AFF'),
      child: Text(
        (w.label ?? '?')[0],
        style: TextStyle(
          color: parseColor(w.textColor ?? '#FFFFFF'),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildChip(BuildContext context, UIWidget w) {
    return Chip(
      label: Text(w.label ?? '', style: const TextStyle(fontSize: 13)),
      backgroundColor: parseColor(w.backgroundColor ?? '#F2F2F7'),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────

  static Color parseColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length == 6) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    if (cleaned.length == 8) {
      return Color(int.parse(cleaned, radix: 16));
    }
    return const Color(0xFF1C1C1E);
  }

  static FontWeight parseFontWeight(String? weight) {
    switch (weight) {
      case 'bold':
        return FontWeight.w700;
      case 'semibold':
        return FontWeight.w600;
      case 'medium':
        return FontWeight.w500;
      case 'light':
        return FontWeight.w300;
      default:
        return FontWeight.w400;
    }
  }

  static IconData mapIcon(String name) {
    switch (name) {
      case 'search':
        return Icons.search;
      case 'home':
        return Icons.home;
      case 'settings':
        return Icons.settings;
      case 'person':
        return Icons.person;
      case 'wifi':
        return Icons.wifi;
      case 'bluetooth':
        return Icons.bluetooth;
      case 'chevron_right':
        return Icons.chevron_right;
      case 'chevron_left':
        return Icons.chevron_left;
      case 'arrow_back':
        return Icons.arrow_back;
      case 'more_horiz':
        return Icons.more_horiz;
      case 'check':
        return Icons.check;
      case 'close':
        return Icons.close;
      case 'add':
        return Icons.add;
      case 'delete':
        return Icons.delete;
      case 'edit':
        return Icons.edit;
      case 'share':
        return Icons.share;
      case 'favorite':
        return Icons.favorite;
      case 'notifications':
        return Icons.notifications;
      case 'camera':
        return Icons.camera;
      case 'photo':
        return Icons.photo;
      case 'mail':
        return Icons.mail;
      case 'call':
        return Icons.call;
      case 'location_on':
        return Icons.location_on;
      case 'lock':
        return Icons.lock;
      case 'info':
        return Icons.info;
      case 'circle':
      default:
        return Icons.circle;
    }
  }
}

/// Subtle pulse animation for the active target button
class _PulseWrapper extends StatefulWidget {
  const _PulseWrapper({required this.child});
  final Widget child;

  @override
  State<_PulseWrapper> createState() => _PulseWrapperState();
}

class _PulseWrapperState extends State<_PulseWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + _controller.value * 0.05,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF007AFF)
                      .withValues(alpha: 0.3 * _controller.value),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
