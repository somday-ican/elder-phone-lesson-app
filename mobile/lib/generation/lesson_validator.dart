import '../models/lesson.dart';

class LessonValidationResult {
  const LessonValidationResult({required this.ok, required this.errors});

  final bool ok;
  final List<String> errors;
}

class LessonValidator {
  const LessonValidator();

  LessonValidationResult validate(Lesson lesson) {
    final errors = <String>[];

    if (lesson.schemaVersion.isEmpty) {
      errors.add('Missing lesson.schemaVersion.');
    }
    if (lesson.id.isEmpty) {
      errors.add('Missing lesson.id.');
    }
    if (lesson.title.isEmpty) {
      errors.add('Missing lesson.title.');
    }
    if (lesson.summary.isEmpty) {
      errors.add('Missing lesson.summary.');
    }
    if (lesson.steps.isEmpty) {
      errors.add('Lesson must include at least one step.');
    }

    for (final indexed in lesson.steps.indexed) {
      _validateStep(indexed.$2, indexed.$1, lesson.source.frameCount, errors);
    }

    return LessonValidationResult(ok: errors.isEmpty, errors: errors);
  }

  void _validateStep(
    LessonStep step,
    int index,
    int frameCount,
    List<String> errors,
  ) {
    if (step.id.isEmpty) {
      errors.add('steps[$index] missing id.');
    }
    if (step.order < 1) {
      errors.add('steps[$index].order must be a positive integer.');
    }
    if (step.title.isEmpty) {
      errors.add('steps[$index] missing title.');
    }
    if (step.instruction.isEmpty) {
      errors.add('steps[$index] missing instruction.');
    }
    if (step.frameIndex < 0 || step.frameIndex >= frameCount) {
      errors.add('steps[$index].frameIndex is outside the extracted frames.');
    }

    final target = step.action.target;
    if (!isRelativeCoordinate(target.x)) {
      errors.add('steps[$index].action.target.x must be between 0 and 1.');
    }
    if (!isRelativeCoordinate(target.y)) {
      errors.add('steps[$index].action.target.y must be between 0 and 1.');
    }
    final width = target.width;
    if (width != null && !isRelativeCoordinate(width)) {
      errors.add('steps[$index].action.target.width must be between 0 and 1.');
    }
    final height = target.height;
    if (height != null && !isRelativeCoordinate(height)) {
      errors.add('steps[$index].action.target.height must be between 0 and 1.');
    }
  }
}
