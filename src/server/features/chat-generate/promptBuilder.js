import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const REF_DIR = (() => {
  try {
    return join(dirname(fileURLToPath(import.meta.url)), "references");
  } catch (_) {
    return join(import.meta.dirname ?? ".", "references");
  }
})();

// Load reference screenshots at module init (lazy, cached)
let _refCache = null;
function getReferenceImages() {
  if (_refCache) return _refCache;
  _refCache = [];
  for (const name of ["wechat-chat-list", "wechat-discover"]) {
    try {
      const b64 = readFileSync(join(REF_DIR, `${name}.txt`), "utf8").trim();
      if (b64) _refCache.push({ name, b64 });
    } catch (_) { /* reference file not found — skip */ }
  }
  return _refCache;
}

export function buildChatGeneratePrompt({ goal, stepCount }) {
  const refs = getReferenceImages();
  const hasRefs = refs.length > 0;

  const system = [
    "You are an expert mobile UI developer who creates PIXEL-PERFECT replicas of Chinese app interfaces.",
    "You specialize in WeChat (微信) UI design patterns and can reproduce the exact layout, spacing, colors, and typography.",
    "Return ONLY valid JSON: {\"html\": \"...\", \"title\": \"...\", \"steps\": [...]}. No markdown fences.",
    "",
    "=== CRITICAL CSS RULES (follow EXACTLY to prevent layout bugs) ===",
    "1. ALWAYS start CSS with: *{margin:0;padding:0;box-sizing:border-box}",
    "2. NEVER use position:absolute without a position:relative parent",
    "3. ALL text must live inside block-level containers (div, span, p, h1-h4, li). NEVER put bare text directly in body or flex containers",
    "4. Use display:flex with align-items:center for vertical centering — NOT manual padding-top hacks",
    "5. Set explicit line-height (1.4) on all text elements to prevent cut-off",
    "6. Phone frame MUST be exactly 375px wide, centered with margin:auto",
    "7. All clickable buttons MUST have cursor:pointer and min-height:44px",
    "8. Use overflow:hidden on containers with border-radius to clip children",
    "9. DO NOT use CSS Grid — only Flexbox (better WebView compatibility)",
    "10. Test your layout mentally: every text string should be inside a proper container"
  ].join("\n");

  const userParts = [
    `An elderly Chinese person wants to learn: "${goal}"`,
    "",
    "Generate a realistic mobile app simulation HTML page that teaches this step by step.",
    `Create exactly ${stepCount} clickable steps.`,
    "",
    "=== WECHAT (微信) DESIGN SPECIFICATION ===",
    "WeChat uses these EXACT colors and patterns:",
    "- Navigation bar background: #EDEDED (light gray, NOT white)",
    "- Navigation bar title: #000000, 17px, font-weight:500 (NOT bold)",
    "- Chat list background: #FFFFFF",
    "- Chat list item: white background, 16px title (#000000), 13px subtitle (#999999)",
    "- Green accent: #07C160 (used for buttons, switches, notification badges)",
    "- Tab bar background: #F7F7F7 with a 0.5px #E6E6E6 top border",
    "- Tab icons: #999999 inactive, #07C160 active",
    "- Font stack: -apple-system, 'PingFang SC', 'Microsoft YaHei', sans-serif",
    "- List dividers: 1px solid #F0F0F0, left-indented 68px",
    "- Rounded corners on cards: 8px",
    "- Typical padding: 12-16px horizontal, 10-12px vertical for list items",
    "- Search bar: #EDEDED background, 6px border-radius, #B3B3B3 placeholder text",
    "",
    "=== HTML PAGE REQUIREMENTS ===",
    "1. Phone frame: 375px wide, centered, rounded corners (36px), shadow, on #E5E5E5 background",
    "2. Status bar (44px, white bg, 9:41 time + signal icons) + Navigation bar (44px, #EDEDED bg) with realistic Chinese title",
    "3. Body content must look like the REAL WeChat app:",
    "   - Chat list items with circular avatars (40px, #07C160 or gray), contact name, last message preview, time",
    "   - Tab bar at bottom with 4 tabs: 微信(💬), 通讯录(👤), 发现(🔍), 我(🙂)",
    "   - Actual Chinese names and realistic message previews",
    "   - Red notification badges (red dot or number in red circle)",
    "4. For EACH of the ${stepCount} steps, create ONE visible clickable target:",
    "   - Must look like a REAL app element (chat item, tab, button, menu item) — NOT a tutorial number",
    "   - onclick=\"onTargetClick(N)\" where N=1,2,3... in order",
    "   - Subtle pulse animation (scale 1→1.03, 1.8s loop)",
    "   - The target should blend naturally into the app UI — it IS the app element itself",
    "",
    "=== JS BRIDGE (INCLUDE EXACTLY) ===",
    "<script>function onTargetClick(n){if(window.TargetBridge)window.TargetBridge.postMessage(JSON.stringify({event:'target_click',stepIndex:n}))}</script>",
    "",
    "=== STEPS ARRAY ===",
    "For each step, one sentence a 70-year-old can follow:",
    "- instruction: like '请点一下绿色「通讯录」按钮'",
    "- elderTip: reassurance, like '如果点错了可以重新来，不用担心'",
    "",
    `Return JSON: {"html":"<!DOCTYPE html>\\n<html lang=\\"zh-CN\\">...","title":"...","steps":[...]}`,
  ];

  // Build user content array — text + optional reference images
  const userContent = [{ type: "text", text: userParts.join("\n") }];

  if (hasRefs) {
    userContent.push({
      type: "text",
      text: "=== REFERENCE: These are real WeChat screenshots. Match this EXACT visual style. ==="
    });
    for (const ref of refs) {
      userContent.push({
        type: "image_url",
        image_url: { url: `data:image/jpeg;base64,${ref.b64}` }
      });
    }
  }

  return { system, userContent };
}
