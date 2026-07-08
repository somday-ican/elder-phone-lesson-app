# Ominigate Setup

This app should not call Ominigate directly from Flutter. Keep API keys on the Node.js backend.

## 1. Configure Backend

Use an OpenAI-compatible Ominigate endpoint:

```bash
export HOST=0.0.0.0
export PORT=3000
export LESSON_GENERATOR_MODE=openai-compatible
export AI_BASE_URL="https://YOUR_OMINIGATE_HOST/v1"
export AI_MODEL_NAME="YOUR_MULTIMODAL_MODEL"
export AI_API_KEY="YOUR_OMINIGATE_API_KEY"
export LESSON_MAX_REQUEST_BYTES=20000000
export LESSON_MAX_FRAME_BYTES=1500000

npm run dev
```

You can also use these aliases:

```bash
export OMINIGATE_BASE_URL="https://YOUR_OMINIGATE_HOST/v1"
export OMINIGATE_API_KEY="YOUR_OMINIGATE_API_KEY"
```

The backend exposes:

```text
POST /api/lessons/generate-multimodal
```

It forwards extracted frame images plus touch-point candidates to Ominigate using an OpenAI-compatible `POST /v1/chat/completions` request.

## 2. Run Flutter Against Backend

Android emulator uses `10.0.2.2` to reach the Mac host:

```bash
cd mobile
flutter run -d emulator-5554 \
  --dart-define=LESSON_API_URL=http://10.0.2.2:3000/api/lessons/generate-multimodal
```

If you run on a real Android device, replace `10.0.2.2` with your Mac LAN IP.

## 3. Expected Ominigate Compatibility

The current backend expects Ominigate to support the OpenAI-compatible Chat Completions shape:

```text
POST {AI_BASE_URL}/chat/completions
Authorization: Bearer {AI_API_KEY}
```

Request content includes:

- a system prompt
- user text instructions
- JPEG frame data URLs in `image_url`
- local touch-point candidates

Response content should be JSON, either:

```json
{ "lesson": { "schemaVersion": "1.0.0", "steps": [] } }
```

or directly:

```json
{ "schemaVersion": "1.0.0", "steps": [] }
```
