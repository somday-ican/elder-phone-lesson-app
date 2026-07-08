import { readJsonBody } from "../../http/readJsonBody.js";
import { sendJson } from "../../http/sendJson.js";
import { buildButtonAnalysisPrompt } from "./promptBuilder.js";

const MAX_REQUEST_BYTES = 2_000_000; // 2MB per request
const MAX_IMAGE_BYTES = 1_500_000;   // 1.5MB per image

export async function analyzeButtonController(req, res, config) {
  const body = await readJsonBody(req, MAX_REQUEST_BYTES);
  if (!body) {
    sendJson(res, 400, { error: "Request body must be valid JSON." });
    return;
  }

  const validation = validateRequest(body);
  if (!validation.ok) {
    sendJson(res, 400, { error: validation.error });
    return;
  }

  const { screenshot, markedPosition, goal } = validation.value;

  // Mock mode — return static analysis
  if (config.lessonGeneratorMode === "mock") {
    sendJson(res, 200, {
      analysis: buildMockAnalysis(markedPosition),
      meta: { generatorMode: "mock" }
    });
    return;
  }

  // Remote mode — call LLM
  try {
    const prompt = buildButtonAnalysisPrompt({ screenshot, markedPosition, goal });

    const response = await fetch(`${config.aiBaseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${config.aiApiKey}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({
        model: config.aiModelName,
        temperature: 0.15,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: prompt.system },
          {
            role: "user",
            content: [
              { type: "text", text: prompt.user },
              {
                type: "image_url",
                image_url: { url: screenshot.image }
              }
            ]
          }
        ]
      })
    });

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(`Model request failed: ${response.status} ${JSON.stringify(payload)}`);
    }

    const content = payload.choices?.[0]?.message?.content;
    if (!content) {
      throw new Error("Model response did not include choices[0].message.content.");
    }

    const parsed = typeof content === "string"
      ? JSON.parse(stripJsonFence(content))
      : content;

    sendJson(res, 200, {
      analysis: parsed,
      meta: { generatorMode: config.lessonGeneratorMode }
    });
  } catch (error) {
    sendJson(res, 500, {
      error: "Button analysis failed.",
      details: process.env.NODE_ENV !== "production" ? error.message : undefined
    });
  }
}

function validateRequest(body) {
  if (!body.screenshot || typeof body.screenshot !== "object") {
    return { ok: false, error: "screenshot is required (object with image and index)." };
  }
  if (!body.screenshot.image || typeof body.screenshot.image !== "string") {
    return { ok: false, error: "screenshot.image is required (base64 data URL)." };
  }
  if (!body.screenshot.image.match(/^data:image\/(png|jpeg|jpg|webp);base64,/)) {
    return { ok: false, error: "screenshot.image must be a base64 data URL (png/jpeg/webp)." };
  }
  if (Buffer.byteLength(body.screenshot.image, "utf8") > MAX_IMAGE_BYTES) {
    return { ok: false, error: `screenshot.image exceeds ${MAX_IMAGE_BYTES} bytes.` };
  }

  if (!body.markedPosition || typeof body.markedPosition !== "object") {
    return { ok: false, error: "markedPosition is required (object with x, y)." };
  }
  if (typeof body.markedPosition.x !== "number" || typeof body.markedPosition.y !== "number") {
    return { ok: false, error: "markedPosition.x and markedPosition.y must be numbers." };
  }
  if (body.markedPosition.x < 0 || body.markedPosition.x > 1 ||
      body.markedPosition.y < 0 || body.markedPosition.y > 1) {
    return { ok: false, error: "markedPosition coordinates must be 0..1." };
  }

  return {
    ok: true,
    value: {
      screenshot: {
        index: Number.isInteger(body.screenshot.index) ? body.screenshot.index : 0,
        image: body.screenshot.image
      },
      markedPosition: { x: body.markedPosition.x, y: body.markedPosition.y },
      goal: typeof body.goal === "string" ? body.goal.slice(0, 200) : ""
    }
  };
}

function buildMockAnalysis(markedPosition) {
  const x = markedPosition.x;
  const y = markedPosition.y;
  return {
    boundingBox: {
      x: Math.round(x * 1000) / 1000,
      y: Math.round(y * 1000) / 1000,
      width: 0.16,
      height: 0.07
    },
    label: "按钮",
    actionDescription: "点击进入下一步",
    instruction: "请点击标注位置的按钮",
    elderTip: "看清楚按钮上的文字再点击",
    buttonStyle: {
      backgroundColor: "#007AFF",
      textColor: "#FFFFFF",
      borderRadius: 10,
      fontSize: 17,
      fontWeight: "bold"
    }
  };
}

function stripJsonFence(value) {
  return value.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
}
