// Widget description protocol — AI generates this JSON,
// widgetFactory renders it as real Flutter widgets.

class UIPage {
  const UIPage({
    required this.title,
    this.backgroundColor = '#F2F2F7',
    this.appBar,
    required this.body,
  });

  final String title;
  final String backgroundColor;
  final UIAppBar? appBar;
  final UIWidget body;

  factory UIPage.fromJson(Map<String, Object?> json) {
    final appBarJson = json['appBar'] as Map<String, Object?>?;
    return UIPage(
      title: json['title'] as String? ?? '',
      backgroundColor: json['backgroundColor'] as String? ?? '#F2F2F7',
      appBar: appBarJson != null ? UIAppBar.fromJson(appBarJson) : null,
      body: UIWidget.fromJson(
        (json['body'] as Map?)?.cast<String, Object?>() ?? {},
      ),
    );
  }
}

class UIAppBar {
  const UIAppBar({
    required this.title,
    this.showBackButton = false,
    this.actions = const [],
  });

  final String title;
  final bool showBackButton;
  final List<UIWidget> actions;

  factory UIAppBar.fromJson(Map<String, Object?> json) {
    return UIAppBar(
      title: json['title'] as String? ?? '',
      showBackButton: json['showBackButton'] as bool? ?? false,
      actions: [
        for (final item in (json['actions'] as List? ?? const []))
          UIWidget.fromJson((item as Map).cast<String, Object?>()),
      ],
    );
  }
}

class UIWidget {
  const UIWidget({
    required this.type,
    this.label,
    this.content,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.children,
    this.icon,
    this.color,
    this.backgroundColor,
    this.textColor,
    this.borderRadius,
    this.fontSize,
    this.fontWeight,
    this.isTarget = false,
    this.stepIndex,
    this.instruction,
    this.elderTip,
    this.value,
    this.showBackButton,
    this.onTap,
    this.imageUrl,
    this.width,
    this.height,
  });

  final String type;
  final String? label;
  final String? content;
  final String? title;
  final String? subtitle;
  final UIWidget? leading;
  final UIWidget? trailing;
  final List<UIWidget>? children;
  final String? icon;
  final String? color;
  final String? backgroundColor;
  final String? textColor;
  final double? borderRadius;
  final double? fontSize;
  final String? fontWeight;
  final bool isTarget;
  final int? stepIndex;
  final String? instruction;
  final String? elderTip;
  final bool? value;
  final bool? showBackButton;
  final Map<String, Object?>? onTap;
  final String? imageUrl;
  final double? width;
  final double? height;

  factory UIWidget.fromJson(Map<String, Object?> json) {
    return UIWidget(
      type: json['type'] as String? ?? 'text',
      label: json['label'] as String?,
      content: json['content'] as String?,
      title: json['title'] as String?,
      subtitle: json['subtitle'] as String?,
      leading: json['leading'] != null
          ? UIWidget.fromJson(
              (json['leading'] as Map).cast<String, Object?>(),
            )
          : null,
      trailing: json['trailing'] != null
          ? UIWidget.fromJson(
              (json['trailing'] as Map).cast<String, Object?>(),
            )
          : null,
      children: json['children'] != null
          ? [
              for (final item in (json['children'] as List))
                UIWidget.fromJson(
                  (item as Map).cast<String, Object?>(),
                ),
            ]
          : null,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      backgroundColor: json['backgroundColor'] as String?,
      textColor: json['textColor'] as String?,
      borderRadius: (json['borderRadius'] as num?)?.toDouble(),
      fontSize: (json['fontSize'] as num?)?.toDouble(),
      fontWeight: json['fontWeight'] as String?,
      isTarget: json['isTarget'] as bool? ?? false,
      stepIndex: (json['stepIndex'] as num?)?.toInt(),
      instruction: json['instruction'] as String?,
      elderTip: json['elderTip'] as String?,
      value: json['value'] as bool?,
      showBackButton: json['showBackButton'] as bool?,
      onTap: (json['onTap'] as Map?)?.cast<String, Object?>(),
      imageUrl: json['imageUrl'] as String?,
      width: (json['width'] as num?)?.toDouble(),
      height: (json['height'] as num?)?.toDouble(),
    );
  }
}
