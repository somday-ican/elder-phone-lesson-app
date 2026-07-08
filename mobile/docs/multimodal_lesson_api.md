# Multimodal Lesson API

Flutter can call a remote multimodal lesson generator by passing:

```bash
flutter run -d emulator-5554 \
  --dart-define=LESSON_API_URL=http://10.0.2.2:3000/api/lessons/generate-multimodal
```

Use `10.0.2.2` from the Android emulator to reach a server running on the host machine.
See `../../docs/ominigate-setup.md` for Ominigate backend environment variables.

## Request

```json
{
  "goal": "把视频里的手机操作讲成适合老人照做的步骤",
  "audience": "elderly smartphone user",
  "prompt": {
    "system": "You generate step-by-step smartphone operation lessons...",
    "user": {}
  },
  "videoMeta": {
    "name": "demo.mp4",
    "type": "video/mp4",
    "duration": 12.5,
    "aspectRatio": 0.5625
  },
  "frames": [
    {
      "index": 0,
      "timeMs": 1200,
      "image": "data:image/jpeg;base64,...",
      "touchCandidate": {
        "x": 0.52,
        "y": 0.74,
        "width": 0.18,
        "height": 0.09,
        "label": "自动识别触摸点"
      }
    }
  ],
  "schema": {
    "schemaVersion": "1.0.0",
    "coordinateSystem": "relative-0-1"
  }
}
```

## Response

Return either a raw lesson object or `{ "lesson": { ... } }`.

Coordinates must use `0..1` relative positions. `x` and `y` are the center of the target area.
