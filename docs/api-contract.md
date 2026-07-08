# API Contract

## POST /api/lessons/generate

Generates an elderly-friendly smartphone operation lesson from extracted video frames. Version 1 uses a mock generator, but the boundary is designed for a future AI model client.

### Request

```json
{
  "goal": "把视频里的手机操作讲成适合老人照做的步骤",
  "audience": "elderly smartphone user",
  "videoMeta": {
    "name": "wechat-pay.mp4",
    "type": "video/mp4",
    "duration": 12.5,
    "width": 1080,
    "height": 1920
  },
  "frames": [
    "data:image/jpeg;base64,..."
  ]
}
```

### Limits

Configured through environment variables:

- `LESSON_MAX_FRAMES`: maximum number of frames, default `8`
- `LESSON_MAX_FRAME_BYTES`: maximum decoded bytes per frame, default `500000`
- `LESSON_MAX_REQUEST_BYTES`: maximum JSON request size, default `7000000`

Frames must be `png`, `jpeg`, `jpg`, or `webp` data URLs.

### Response

```json
{
  "lesson": {
    "schemaVersion": "1.0.0",
    "id": "lesson_123",
    "title": "老人手机操作指导教程",
    "summary": "根据上传视频生成的教程",
    "createdAt": "2026-07-08T00:00:00.000Z",
    "source": {
      "type": "video_frames",
      "frameCount": 4,
      "generator": "mock"
    },
    "steps": [
      {
        "id": "step_1",
        "order": 1,
        "title": "轻点目标按钮",
        "instruction": "用手指轻轻点一下高亮位置。",
        "action": {
          "type": "tap",
          "target": {
            "x": 0.72,
            "y": 0.78,
            "width": 0.22,
            "height": 0.1,
            "label": "下一步按钮"
          }
        },
        "frameIndex": 0,
        "elderTip": "点击后等一两秒。"
      }
    ]
  },
  "meta": {
    "generatorMode": "mock",
    "promptPreview": {
      "goal": "把视频里的手机操作讲成适合老人照做的步骤",
      "audience": "elderly smartphone user",
      "videoMeta": {},
      "frameCount": 4,
      "frameFormat": "base64 data URLs"
    },
    "limits": {
      "maxFrames": 8,
      "maxFrameBytes": 500000
    }
  }
}
```

### Lesson Schema Notes

- Coordinates are relative to the rendered frame.
- `x`, `y`, `width`, and `height` are numbers from `0` to `1`.
- `x` and `y` represent the center point of the target area.
- `width` and `height` are optional target dimensions.

### Error Responses

```json
{ "error": "Too many frames. Maximum is 8." }
```

Common statuses:

- `400`: invalid JSON, missing frames, unsupported frame data URL, too many frames
- `413`: request body or frame is too large
- `500`: generated lesson failed schema validation or unexpected server error
