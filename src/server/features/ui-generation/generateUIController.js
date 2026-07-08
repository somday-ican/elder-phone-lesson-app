import { readJsonBody } from "../../http/readJsonBody.js";
import { sendJson } from "../../http/sendJson.js";
import { buildUIGenerationPrompt } from "./promptBuilder.js";

const MAX_REQUEST_BYTES = 10_000_000;
const MAX_IMAGE_BYTES = 1_500_000;
const MAX_SCREENSHOTS = 8;

export async function generateUIController(req, res, config) {
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

  const { screenshots, markedPositions, goal } = validation.value;

  // Mock mode
  if (config.lessonGeneratorMode === "mock") {
    sendJson(res, 200, {
      page: buildMockPage(markedPositions),
      meta: { generatorMode: "mock" }
    });
    return;
  }

  // Remote LLM call
  try {
    const prompt = buildUIGenerationPrompt({ screenshots, markedPositions, goal });

    const userContent = [
      { type: "text", text: prompt.user },
      ...screenshots.flatMap((s) => [
        { type: "text", text: `Screenshot ${s.index + 1}:` },
        { type: "image_url", image_url: { url: s.image } }
      ])
    ];

    const response = await fetch(`${config.aiBaseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${config.aiApiKey}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({
        model: config.aiModelName,
        temperature: 0.2,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: prompt.system },
          { role: "user", content: userContent }
        ]
      })
    });

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(`Model request failed: ${response.status} ${JSON.stringify(payload)}`);
    }

    const content = payload.choices?.[0]?.message?.content;
    if (!content) {
      throw new Error("Model response missing choices[0].message.content.");
    }

    const parsed = typeof content === "string"
      ? JSON.parse(stripJsonFence(content))
      : content;

    sendJson(res, 200, {
      page: parsed.page || parsed,
      meta: { generatorMode: config.lessonGeneratorMode }
    });
  } catch (error) {
    sendJson(res, 500, {
      error: "UI generation failed.",
      details: process.env.NODE_ENV !== "production" ? error.message : undefined
    });
  }
}

function validateRequest(body) {
  if (!Array.isArray(body.screenshots) || body.screenshots.length === 0) {
    return { ok: false, error: "screenshots must be a non-empty array." };
  }
  if (body.screenshots.length > MAX_SCREENSHOTS) {
    return { ok: false, error: `Maximum ${MAX_SCREENSHOTS} screenshots allowed.` };
  }

  for (const [i, s] of body.screenshots.entries()) {
    if (!s || typeof s !== "object") {
      return { ok: false, error: `screenshots[${i}] must be an object.` };
    }
    if (!s.image || typeof s.image !== "string") {
      return { ok: false, error: `screenshots[${i}].image is required.` };
    }
    if (!s.image.match(/^data:image\/(png|jpeg|jpg|webp);base64,/)) {
      return { ok: false, error: `screenshots[${i}].image must be a base64 data URL.` };
    }
    if (Buffer.byteLength(s.image, "utf8") > MAX_IMAGE_BYTES) {
      return { ok: false, error: `screenshots[${i}].image exceeds ${MAX_IMAGE_BYTES} bytes.` };
    }
  }

  if (!Array.isArray(body.markedPositions) || body.markedPositions.length === 0) {
    return { ok: false, error: "markedPositions must be a non-empty array." };
  }

  for (const [i, m] of body.markedPositions.entries()) {
    if (!m || typeof m !== "object") {
      return { ok: false, error: `markedPositions[${i}] must be an object.` };
    }
    if (typeof m.x !== "number" || typeof m.y !== "number") {
      return { ok: false, error: `markedPositions[${i}] requires x and y numbers.` };
    }
    if (m.x < 0 || m.x > 1 || m.y < 0 || m.y > 1) {
      return { ok: false, error: `markedPositions[${i}] coordinates must be 0..1.` };
    }
  }

  return {
    ok: true,
    value: {
      screenshots: body.screenshots.map((s, i) => ({
        index: Number.isInteger(s.index) ? s.index : i,
        image: s.image
      })),
      markedPositions: body.markedPositions.map(m => ({ x: m.x, y: m.y })),
      goal: typeof body.goal === "string" ? body.goal.slice(0, 200) : ""
    }
  };
}

function buildMockPage(markedPositions) {
  const steps = markedPositions.map((pos, i) => ({
    type: "button",
    label: `步骤 ${i + 1}`,
    backgroundColor: "#007AFF",
    textColor: "#FFFFFF",
    borderRadius: 12,
    fontSize: 17,
    fontWeight: "bold",
    isTarget: true,
    stepIndex: i + 1,
    instruction: `请点击第 ${i + 1} 个按钮，位置在屏幕${pos.y < 0.5 ? '上' : '下'}方`
  }));

  return {
    title: "操作练习",
    backgroundColor: "#F2F2F7",
    appBar: {
      title: "操作练习",
      showBackButton: false,
      actions: []
    },
    body: {
      type: "column",
      children: [
        {
          type: "text",
          content: "请依次点击下面的按钮",
          fontSize: 16,
          fontWeight: "bold",
          color: "#333333"
        },
        { type: "divider" },
        ...steps
      ]
    }
  };
}

function stripJsonFence(value) {
  return value.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
}
