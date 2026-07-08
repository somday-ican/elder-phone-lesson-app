# Architecture

## Current Stack

The repository was empty when this module was added, so the first version uses a small zero-dependency Node.js HTTP server and a native browser frontend.

- Server entry: `src/server/index.js`
- Feature backend: `src/server/features/video-to-lesson`
- Shared schema: `src/shared/lessonSchema.js`
- Frontend: `public/index.html`, `public/video-to-lesson.js`, `public/styles.css`
- Local bind defaults: `HOST=127.0.0.1`, `PORT=3000`

## Feature Flow

1. User selects a local video in the browser.
2. The frontend loads the video into a hidden canvas workflow.
3. The browser extracts up to `MAX_FRAMES` compressed JPEG frame data URLs.
4. The user previews the extracted frames.
5. The frontend sends `frames` plus lightweight video metadata to `POST /api/lessons/generate`.
6. The backend validates request size, frame count, frame data URL type, and decoded image size.
7. `PromptBuilder` creates the future model prompt payload.
8. `MockLessonGenerator` returns a schema-shaped lesson.
9. `LessonValidator` validates required fields and relative coordinates.
10. The frontend renders lesson steps and highlights relative target coordinates on the selected frame.

## Backend Boundaries

The first version does not call a real AI service. These classes reserve the integration seams:

- `PromptBuilder`: owns system/user prompt construction.
- `ModelClient`: future external model integration.
- `MockLessonGenerator`: local deterministic generator for development.
- `LessonValidator`: validates AI or mock output before returning it to clients.

To connect a real AI model later:

1. Implement `ModelClient.generateLessonJson({ frames, videoMeta, audience, goal, prompt })`.
2. Set `LESSON_GENERATOR_MODE` to a non-`mock` value.
3. Keep the validator in the response path so malformed model output is rejected before the UI consumes it.

## Constraints

This feature intentionally excludes:

- Login and account state
- Payments
- Complex database persistence
- Cloud object storage

The browser sends base64 frames directly to the backend. This keeps the first version simple, but production should move large videos/images to object storage and pass signed URLs or file IDs to the generator pipeline.
