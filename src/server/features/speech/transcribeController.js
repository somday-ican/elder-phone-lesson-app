import { readJsonBody } from "../../http/readJsonBody.js";
import { sendJson } from "../../http/sendJson.js";
import { buildTranscribePrompt } from "./transcribePrompt.js";

const MAX_BYTES = 500000;

export async function transcribeController(req, res, config) {
  const body = await readJsonBody(req, MAX_BYTES);
  if (!body || typeof body.audio !== "string") {
    sendJson(res, 400, { error: "audio base64 string required." });
    return;
  }

  if (!body.audio.match(/^data:audio\/(wav|webm|mp3|m4a|ogg);base64,/)) {
    sendJson(res, 400, { error: "audio must be a base64 data URL (wav/webm/mp3/m4a/ogg)." });
    return;
  }

  if (config.lessonGeneratorMode === "mock") {
    sendJson(res, 200, { text: "语音识别模拟结果", meta: { generatorMode: "mock" } });
    return;
  }

  try {
    const prompt = buildTranscribePrompt();

    const response = await fetch(`${config.aiBaseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${config.aiApiKey}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({
        model: config.aiModelName,
        temperature: 0,
        max_tokens: 256,
        messages: [
          { role: "system", content: prompt.system },
          {
            role: "user",
            content: [
              { type: "text", text: prompt.user },
              {
                type: "input_audio",
                input_audio: {
                  data: body.audio,
                  format: "wav"
                }
              }
            ]
          }
        ]
      })
    });

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(`Model request failed: ${response.status} ${JSON.stringify(payload).slice(0, 200)}`);
    }

    const text = (payload.choices?.[0]?.message?.content || "").trim();
    sendJson(res, 200, { text, meta: { generatorMode: config.lessonGeneratorMode } });
  } catch (error) {
    sendJson(res, 500, {
      error: "Transcription failed.",
      details: process.env.NODE_ENV !== "production" ? error.message : undefined
    });
  }
}
