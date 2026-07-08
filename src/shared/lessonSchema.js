export const LESSON_SCHEMA_VERSION = "1.0.0";

export const lessonActionTypes = [
  "tap",
  "long_press",
  "swipe",
  "type",
  "wait",
  "observe"
];

export const lessonSchema = {
  schemaVersion: LESSON_SCHEMA_VERSION,
  coordinateSystem: "relative-0-1",
  requiredTopLevelFields: [
    "id",
    "title",
    "summary",
    "steps",
    "createdAt",
    "source"
  ],
  stepShape: {
    id: "string",
    order: "number",
    title: "string",
    instruction: "string",
    action: {
      type: lessonActionTypes,
      target: {
        x: "number 0..1",
        y: "number 0..1",
        width: "number 0..1 optional",
        height: "number 0..1 optional",
        label: "string optional"
      }
    },
    frameIndex: "number",
    elderTip: "string optional"
  }
};

export function isRelativeCoordinate(value) {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 1;
}
