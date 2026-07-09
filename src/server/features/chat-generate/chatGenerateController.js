import { readJsonBody } from "../../http/readJsonBody.js";
import { sendJson } from "../../http/sendJson.js";
import { buildChatGeneratePrompt } from "./promptBuilder.js";

const MAX_REQUEST_BYTES = 500000; // increased for screenshot base64 payloads
const MAX_GOAL_LENGTH = 200;
const MAX_STEP_COUNT = 8;
const MIN_STEP_COUNT = 3;

export async function chatGenerateController(req, res, config) {
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

  const { goal, stepCount } = validation.value;
  const customScreenshots = validateScreenshots(body.screenshots);

  // Mock mode — return static result
  if (config.lessonGeneratorMode === "mock") {
    sendJson(res, 200, {
      html: buildMockHtml(goal, stepCount),
      title: goal,
      steps: buildMockSteps(stepCount),
      meta: { generatorMode: "mock" }
    });
    return;
  }

  // Remote LLM call — no images, just text prompt
  try {
    const prompt = buildChatGeneratePrompt({ goal, stepCount, customScreenshots });

    const response = await fetch(`${config.aiBaseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${config.aiApiKey}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({
        model: config.aiModelName,
        temperature: 0.35,
        top_p: 0.9,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: prompt.system },
          { role: "user", content: prompt.userContent }
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
      html: parsed.html || "",
      title: parsed.title || goal,
      steps: Array.isArray(parsed.steps) ? parsed.steps : buildMockSteps(stepCount),
      meta: { generatorMode: config.lessonGeneratorMode }
    });
  } catch (error) {
    sendJson(res, 500, {
      error: "Chat generation failed.",
      details: process.env.NODE_ENV !== "production" ? error.message : undefined
    });
  }
}

function validateScreenshots(screenshots) {
  if (!Array.isArray(screenshots)) return [];
  return screenshots.filter(s =>
    typeof s === "string" && s.match(/^data:image\/(png|jpeg|jpg|webp);base64,/)
  ).slice(0, 6);
}

function validateRequest(body) {
  if (typeof body.goal !== "string" || body.goal.trim().length === 0) {
    return { ok: false, error: "goal is required (non-empty string)." };
  }
  const goal = body.goal.trim().slice(0, MAX_GOAL_LENGTH);

  const stepCount = Number.isInteger(body.stepCount)
    ? body.stepCount
    : 5;
  if (stepCount < MIN_STEP_COUNT || stepCount > MAX_STEP_COUNT) {
    return { ok: false, error: `stepCount must be ${MIN_STEP_COUNT}-${MAX_STEP_COUNT}.` };
  }

  return { ok: true, value: { goal, stepCount } };
}

function buildMockSteps(stepCount) {
  const steps = [];
  for (let i = 0; i < stepCount; i++) {
    steps.push({
      stepIndex: i + 1,
      instruction: `请点击第 ${i + 1} 步的按钮`,
      elderTip: "慢慢来，不着急"
    });
  }
  return steps;
}

function buildMockHtml(goal, stepCount) {
  const buttons = [];
  for (let i = 0; i < stepCount; i++) {
    buttons.push(`
      <button onclick="onTargetClick(${i + 1})" class="target"
              style="background:#007AFF;color:#fff;border:none;padding:14px 28px;
                     border-radius:12px;font-size:17px;font-weight:600;margin:8px 0;
                     cursor:pointer;width:100%;max-width:280px;animation:pulse 1.5s infinite;">
        步骤 ${i + 1}
      </button>`);
  }

  return `<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=no">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
     background:#e5e5e5;display:flex;justify-content:center;align-items:center;
     min-height:100vh;padding:16px}
.phone{width:375px;background:#F2F2F7;border-radius:36px;overflow:hidden;
       box-shadow:0 20px 60px rgba(0,0,0,0.3),0 0 0 2px #1a1a1a;min-height:680px}
.status-bar{height:44px;background:#fff;display:flex;align-items:center;
            justify-content:space-between;padding:0 24px;font-size:13px;
            font-weight:600;color:#1c1c1e}
.nav-bar{height:52px;background:#fff;display:flex;align-items:center;
         justify-content:center;padding:0 16px;border-bottom:1px solid #e5e5ea;
         font-size:18px;font-weight:700;color:#1c1c1e}
.content{padding:28px 20px;display:flex;flex-direction:column;align-items:center}
h2{font-size:23px;font-weight:800;color:#1c1c1e;margin-bottom:6px}
p.sub{font-size:15px;color:#8e8e93;margin-bottom:20px;text-align:center;line-height:1.5}
@keyframes pulse{0%,100%{transform:scale(1);box-shadow:0 0 0 0 rgba(0,122,255,0.4)}
                  50%{transform:scale(1.04);box-shadow:0 0 0 14px rgba(0,122,255,0)}}
.target{box-shadow:0 4px 14px rgba(0,0,0,0.12);transition:transform 0.15s}
.target:active{transform:scale(0.94)!important}
</style></head>
<body><div class="phone">
<div class="status-bar"><span>9:41</span><span>📶 🔋</span></div>
<div class="nav-bar">${escapeHtml(goal)}</div>
<div class="content">
<h2>📚 操作教程</h2>
<p class="sub">请按照数字顺序<br>依次点击下方按钮</p>
${buttons.join("\n")}
</div>
</div>
<script>function onTargetClick(n){if(window.TargetBridge)window.TargetBridge.postMessage(JSON.stringify({event:"target_click",stepIndex:n}))}</script>
</body></html>`;
}

function escapeHtml(str) {
  return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function stripJsonFence(value) {
  return value.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
}
