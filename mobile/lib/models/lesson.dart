enum LessonActionType {
  tap,
  longPress,
  swipe,
  type,
  wait,
  observe;

  String get wireName {
    switch (this) {
      case LessonActionType.longPress:
        return 'long_press';
      case LessonActionType.tap:
      case LessonActionType.swipe:
      case LessonActionType.type:
      case LessonActionType.wait:
      case LessonActionType.observe:
        return name;
    }
  }

  static LessonActionType fromWireName(String value) {
    return LessonActionType.values.firstWhere(
      (type) => type.wireName == value,
      orElse: () => LessonActionType.observe,
    );
  }
}

const lessonSchemaVersion = '1.0.0';

class Lesson {
  const Lesson({
    required this.schemaVersion,
    required this.id,
    required this.title,
    required this.summary,
    required this.createdAt,
    required this.source,
    required this.steps,
  });

  final String schemaVersion;
  final String id;
  final String title;
  final String summary;
  final DateTime createdAt;
  final LessonSource source;
  final List<LessonStep> steps;

  factory Lesson.fromJson(Map<String, Object?> json) {
    return Lesson(
      schemaVersion: json['schemaVersion'] as String? ?? '',
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      source: LessonSource.fromJson(
        (json['source'] as Map?)?.cast<String, Object?>() ?? {},
      ),
      steps: [
        for (final item in (json['steps'] as List? ?? const []))
          LessonStep.fromJson((item as Map).cast<String, Object?>()),
      ],
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'id': id,
      'title': title,
      'summary': summary,
      'createdAt': createdAt.toIso8601String(),
      'source': source.toJson(),
      'steps': [for (final step in steps) step.toJson()],
    };
  }
}

class LessonSource {
  const LessonSource({
    required this.type,
    required this.frameCount,
    required this.generator,
  });

  final String type;
  final int frameCount;
  final String generator;

  factory LessonSource.fromJson(Map<String, Object?> json) {
    return LessonSource(
      type: json['type'] as String? ?? '',
      frameCount: (json['frameCount'] as num?)?.toInt() ?? 0,
      generator: json['generator'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() {
    return {'type': type, 'frameCount': frameCount, 'generator': generator};
  }
}

class LessonStep {
  const LessonStep({
    required this.id,
    required this.order,
    required this.title,
    required this.instruction,
    required this.action,
    required this.frameIndex,
    this.elderTip,
  });

  final String id;
  final int order;
  final String title;
  final String instruction;
  final LessonAction action;
  final int frameIndex;
  final String? elderTip;

  factory LessonStep.fromJson(Map<String, Object?> json) {
    return LessonStep(
      id: json['id'] as String? ?? '',
      order: (json['order'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      instruction: json['instruction'] as String? ?? '',
      action: LessonAction.fromJson(
        (json['action'] as Map?)?.cast<String, Object?>() ?? {},
      ),
      frameIndex: (json['frameIndex'] as num?)?.toInt() ?? 0,
      elderTip: json['elderTip'] as String?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'order': order,
      'title': title,
      'instruction': instruction,
      'action': action.toJson(),
      'frameIndex': frameIndex,
      if (elderTip != null) 'elderTip': elderTip,
    };
  }
}

class LessonAction {
  const LessonAction({required this.type, required this.target});

  final LessonActionType type;
  final RelativeTarget target;

  factory LessonAction.fromJson(Map<String, Object?> json) {
    return LessonAction(
      type: LessonActionType.fromWireName(json['type'] as String? ?? ''),
      target: RelativeTarget.fromJson(
        (json['target'] as Map?)?.cast<String, Object?>() ?? {},
      ),
    );
  }

  Map<String, Object?> toJson() {
    return {'type': type.wireName, 'target': target.toJson()};
  }
}

class RelativeTarget {
  const RelativeTarget({
    required this.x,
    required this.y,
    this.width,
    this.height,
    this.label,
  });

  final double x;
  final double y;
  final double? width;
  final double? height;
  final String? label;

  factory RelativeTarget.fromJson(Map<String, Object?> json) {
    return RelativeTarget(
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble(),
      height: (json['height'] as num?)?.toDouble(),
      label: json['label'] as String?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'x': x,
      'y': y,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (label != null) 'label': label,
    };
  }
}

bool isRelativeCoordinate(num value) => value >= 0 && value <= 1;
