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
      html: buildMockHtml(markedPositions),
      title: "操作练习",
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
        temperature: 0.3,
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
      html: parsed.html,
      title: parsed.title || "操作练习",
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

function buildMockHtml(markedPositions) {
  const buttons = markedPositions.map((_, i) => `
    <button class="target-btn" onclick="onTargetClick(${i + 1})"
            style="background:#007AFF;color:#fff;border:none;padding:16px 32px;
                   border-radius:12px;font-size:18px;font-weight:600;margin:10px 0;
                   cursor:pointer;width:100%;max-width:300px;animation:pulse 1.5s infinite;">
      📱 步骤 ${i + 1}
    </button>`).join('\n');

  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=1.0">
<style>
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
     background:#e5e5e5;display:flex;justify-content:center;align-items:center;
     min-height:100vh;padding:20px;}
.phone{width:375px;background:#F2F2F7;border-radius:32px;overflow:hidden;
       box-shadow:0 20px 60px rgba(0,0,0,0.3),0 0 0 2px #1a1a1a;min-height:700px;}
.status-bar{height:44px;background:#fff;display:flex;align-items:center;
            justify-content:space-between;padding:0 24px;font-size:13px;font-weight:600;}
.nav-bar{height:52px;background:#fff;display:flex;align-items:center;padding:0 16px;
         border-bottom:1px solid #e5e5ea;font-size:18px;font-weight:700;justify-content:center;}
.content{padding:24px 20px;display:flex;flex-direction:column;align-items:center;gap:12px;}
.title{font-size:22px;font-weight:700;color:#1c1c1e;text-align:center;margin-bottom:8px;}
.subtitle{font-size:15px;color:#8e8e93;text-align:center;margin-bottom:16px;}
@keyframes pulse{0%,100%{transform:scale(1);box-shadow:0 0 0 0 rgba(0,122,255,0.4);}
                  50%{transform:scale(1.04);box-shadow:0 0 0 12px rgba(0,122,255,0);}}
.target-btn{transition:transform 0.15s ease;}
.target-btn:active{transform:scale(0.94)!important;}
</style>
</head>
<body>
<div class="phone">
  <div class="status-bar"><span>9:41</span><span>📶 🔋</span></div>
  <div class="nav-bar">操作练习</div>
  <div class="content">
    <div class="title">操作练习</div>
    <div class="subtitle">请依次点击下面的按钮，完成操作步骤</div>
    ${buttons}
    <p style="color:#8e8e93;font-size:13px;margin-top:20px;">共 ${markedPositions.length} 个步骤</p>
  </div>
</div>
<script>
function onTargetClick(step) {
  if (window.TargetBridge) {
    window.TargetBridge.postMessage(JSON.stringify({event:"target_click",stepIndex:step}));
  }
}
function onWrongClick() {
  if (window.TargetBridge) {
    window.TargetBridge.postMessage(JSON.stringify({event:"wrong_click"}));
  }
}
</script>
</body>
</html>`;
}

function stripJsonFence(value) {
  return value.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
}
