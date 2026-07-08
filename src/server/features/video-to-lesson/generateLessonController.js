import { readJsonBody } from "../../http/readJsonBody.js";
import { sendJson } from "../../http/sendJson.js";
import { LessonValidator } from "./lessonValidator.js";
import { MockLessonGenerator } from "./mockLessonGenerator.js";
import { ModelClient } from "./modelClient.js";
import { PromptBuilder } from "./promptBuilder.js";
import { validateGenerateLessonRequest } from "./frameRequestValidator.js";

export async function generateLessonController(req, res, config) {
  const body = await readJsonBody(req, config.lessonMaxRequestBytes);
  const request = validateGenerateLessonRequest(body, config);

  if (!request.ok) {
    sendJson(res, request.statusCode, { error: request.message });
    return;
  }

  const promptBuilder = new PromptBuilder();
  const prompt = promptBuilder.build(request.value);
  const generator = createGenerator(config);
  const validator = new LessonValidator();

  const lesson = await generator.generate({ ...request.value, prompt });
  const validation = validator.validate(lesson);

  if (!validation.ok) {
    sendJson(res, 500, {
      error: "Generated lesson did not match schema.",
      details: validation.errors
    });
    return;
  }

  sendJson(res, 200, {
    lesson,
    meta: {
      generatorMode: config.lessonGeneratorMode,
      promptPreview: prompt.user,
      limits: {
        maxFrames: config.lessonMaxFrames,
        maxFrameBytes: config.lessonMaxFrameBytes
      }
    }
  });
}

function createGenerator(config) {
  if (config.lessonGeneratorMode === "mock") {
    return new MockLessonGenerator();
  }

  return new ModelClient({
    mode: config.lessonGeneratorMode,
    baseUrl: config.aiBaseUrl,
    modelName: config.aiModelName,
    apiKey: config.aiApiKey
  });
}
