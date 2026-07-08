import { isRelativeCoordinate, lessonActionTypes } from "../../../shared/lessonSchema.js";

export class LessonValidator {
  validate(lesson) {
    const errors = [];

    if (!lesson || typeof lesson !== "object") {
      return { ok: false, errors: ["Lesson must be an object."] };
    }

    for (const field of ["schemaVersion", "id", "title", "summary", "createdAt", "source"]) {
      if (!lesson[field]) {
        errors.push(`Missing lesson.${field}.`);
      }
    }

    if (!Array.isArray(lesson.steps) || lesson.steps.length === 0) {
      errors.push("Lesson must include at least one step.");
    } else {
      lesson.steps.forEach((step, index) => {
        validateStep(step, index, errors);
      });
    }

    return { ok: errors.length === 0, errors };
  }
}

function validateStep(step, index, errors) {
  if (!step || typeof step !== "object") {
    errors.push(`steps[${index}] must be an object.`);
    return;
  }

  for (const field of ["id", "order", "title", "instruction", "action", "frameIndex"]) {
    if (step[field] === undefined || step[field] === null || step[field] === "") {
      errors.push(`steps[${index}] missing ${field}.`);
    }
  }

  if (!Number.isInteger(step.order) || step.order < 1) {
    errors.push(`steps[${index}].order must be a positive integer.`);
  }

  if (!Number.isInteger(step.frameIndex) || step.frameIndex < 0) {
    errors.push(`steps[${index}].frameIndex must be a non-negative integer.`);
  }

  const action = step.action;
  if (!action || typeof action !== "object") {
    errors.push(`steps[${index}].action must be an object.`);
    return;
  }

  if (!lessonActionTypes.includes(action.type)) {
    errors.push(`steps[${index}].action.type is invalid.`);
  }

  const target = action.target;
  if (!target || typeof target !== "object") {
    errors.push(`steps[${index}].action.target must be an object.`);
    return;
  }

  for (const coordinate of ["x", "y"]) {
    if (!isRelativeCoordinate(target[coordinate])) {
      errors.push(`steps[${index}].action.target.${coordinate} must be between 0 and 1.`);
    }
  }

  for (const dimension of ["width", "height"]) {
    if (target[dimension] !== undefined && !isRelativeCoordinate(target[dimension])) {
      errors.push(`steps[${index}].action.target.${dimension} must be between 0 and 1.`);
    }
  }
}
