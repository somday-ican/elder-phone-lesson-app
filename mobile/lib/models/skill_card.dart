import 'dart:convert';
import 'package:uuid/uuid.dart';

class SkillCard {
  SkillCard({
    required this.id,
    required this.title,
    required this.html,
    required this.stepCount,
    required this.createdAt,
    this.timesPracticed = 0,
  });

  factory SkillCard.create({
    required String title,
    required String html,
    required int stepCount,
  }) {
    return SkillCard(
      id: const Uuid().v4(),
      title: title,
      html: html,
      stepCount: stepCount,
      createdAt: DateTime.now(),
    );
  }

  final String id;
  final String title;
  final String html;
  final int stepCount;
  final DateTime createdAt;
  final int timesPracticed;

  SkillCard copyWith({
    String? title,
    int? timesPracticed,
  }) {
    return SkillCard(
      id: id,
      title: title ?? this.title,
      html: html,
      stepCount: stepCount,
      createdAt: createdAt,
      timesPracticed: timesPracticed ?? this.timesPracticed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'html': html,
      'stepCount': stepCount,
      'createdAt': createdAt.toIso8601String(),
      'timesPracticed': timesPracticed,
    };
  }

  factory SkillCard.fromJson(Map<String, dynamic> json) {
    return SkillCard(
      id: json['id'] as String? ?? const Uuid().v4(),
      title: json['title'] as String? ?? '',
      html: json['html'] as String? ?? '',
      stepCount: (json['stepCount'] as num?)?.toInt() ?? 3,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      timesPracticed: (json['timesPracticed'] as num?)?.toInt() ?? 0,
    );
  }

  static String encodeList(List<SkillCard> cards) {
    return jsonEncode([for (final c in cards) c.toJson()]);
  }

  static List<SkillCard> decodeList(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((e) => SkillCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
