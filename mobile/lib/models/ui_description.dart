/// Result from the UI generation API — contains AI-generated HTML.
class UIGenerationResult {
  const UIGenerationResult({
    required this.html,
    required this.title,
  });

  final String html;
  final String title;

  factory UIGenerationResult.fromJson(Map<String, Object?> json) {
    return UIGenerationResult(
      html: json['html'] as String? ?? '',
      title: json['title'] as String? ?? '操作练习',
    );
  }
}
