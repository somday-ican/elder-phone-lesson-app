import 'lesson.dart';

class ButtonAnalysis {
  const ButtonAnalysis({
    required this.boundingBox,
    required this.label,
    required this.actionDescription,
    required this.instruction,
    required this.elderTip,
    required this.buttonStyle,
  });

  final BoundingBox boundingBox;
  final String label;
  final String actionDescription;
  final String instruction;
  final String elderTip;
  final ButtonStyleInfo buttonStyle;

  factory ButtonAnalysis.fromJson(Map<String, Object?> json) {
    final box = (json['boundingBox'] as Map?)?.cast<String, Object?>() ?? {};
    final style =
        (json['buttonStyle'] as Map?)?.cast<String, Object?>() ?? {};
    return ButtonAnalysis(
      boundingBox: BoundingBox.fromJson(box),
      label: json['label'] as String? ?? '',
      actionDescription: json['actionDescription'] as String? ?? '',
      instruction: json['instruction'] as String? ?? '',
      elderTip: json['elderTip'] as String? ?? '',
      buttonStyle: ButtonStyleInfo.fromJson(style),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'boundingBox': boundingBox.toJson(),
      'label': label,
      'actionDescription': actionDescription,
      'instruction': instruction,
      'elderTip': elderTip,
      'buttonStyle': buttonStyle.toJson(),
    };
  }
}

class BoundingBox {
  const BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  RelativeTarget toRelativeTarget({String? label}) {
    return RelativeTarget(
      x: x,
      y: y,
      width: width,
      height: height,
      label: label ?? '按钮',
    );
  }

  factory BoundingBox.fromJson(Map<String, Object?> json) {
    return BoundingBox(
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 0.16,
      height: (json['height'] as num?)?.toDouble() ?? 0.07,
    );
  }

  Map<String, Object?> toJson() {
    return {'x': x, 'y': y, 'width': width, 'height': height};
  }
}

class ButtonStyleInfo {
  const ButtonStyleInfo({
    required this.backgroundColor,
    required this.textColor,
    required this.borderRadius,
    required this.fontSize,
    required this.fontWeight,
  });

  final String backgroundColor;
  final String textColor;
  final double borderRadius;
  final double fontSize;
  final String fontWeight;

  factory ButtonStyleInfo.fromJson(Map<String, Object?> json) {
    return ButtonStyleInfo(
      backgroundColor: json['backgroundColor'] as String? ?? '#007AFF',
      textColor: json['textColor'] as String? ?? '#FFFFFF',
      borderRadius: (json['borderRadius'] as num?)?.toDouble() ?? 10,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 17,
      fontWeight: json['fontWeight'] as String? ?? 'bold',
    );
  }

  Map<String, Object?> toJson() {
    return {
      'backgroundColor': backgroundColor,
      'textColor': textColor,
      'borderRadius': borderRadius,
      'fontSize': fontSize,
      'fontWeight': fontWeight,
    };
  }
}
