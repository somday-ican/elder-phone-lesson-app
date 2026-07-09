import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const REF_DIR = (() => {
  try { return join(dirname(fileURLToPath(import.meta.url)), "references"); }
  catch (_) { return join(import.meta.dirname ?? ".", "references"); }
})();

// All reference images live in references/*.txt as base64 JPEG data
let _refCache = null;
function getAllReferenceImages() {
  if (_refCache) return _refCache;
  _refCache = [];
  try {
    const files = readdirSync(REF_DIR).filter(f => f.endsWith('.txt'));
    for (const f of files) {
      try {
        const b64 = readFileSync(join(REF_DIR, f), "utf8").trim();
        if (b64) _refCache.push({ name: f.replace('.txt', ''), b64 });
      } catch (_) {}
    }
  } catch (_) {
    // Fallback: load known files
    for (const name of ["wechat-chat-list", "wechat-discover"]) {
      try {
        const b64 = readFileSync(join(REF_DIR, `${name}.txt`), "utf8").trim();
        if (b64) _refCache.push({ name, b64 });
      } catch (_) {}
    }
  }
  return _refCache;
}

// ── Stage 1: Scene Understanding ──────────────────────────────────

export function buildStage1Prompt({ goal, stepCount }) {
  const system = [
    "You are a mobile app interaction expert who understands smartphone UI patterns.",
    "Your task is to analyze a user's goal and plan a step-by-step tutorial.",
    "You know the visual design and interaction patterns of Chinese apps:",
    "- WeChat (微信): green #07C160, bottom 4-tab bar (微信/通讯录/发现/我), #EDEDED nav bar",
    "- Alipay (支付宝): blue #1677FF, bottom 5-tab bar, white bg, card-based layout",
    "- Taobao (淘宝): orange #FF5000, top search bar, card grid products",
    "- Meituan (美团): yellow #FFD300, food cards, bottom 5-tab bar",
    "- Douyin (抖音): black bg, infinite scroll video feed, bottom 5-tab bar",
    "- Xiaohongshu (小红书): red #FF2442, waterfall grid cards, bottom 5-tab bar",
    "- Gaode Maps (高德地图): blue #0091FF, map base, bottom search bar",
    "- Any other app: infer reasonable colors and layout from the app's identity and purpose",
    "Return ONLY valid JSON. No markdown fences."
  ].join(" ");

  const user = [
    `A 70-year-old Chinese person wants to learn: "${goal}"`,
    `The tutorial will have exactly ${stepCount} steps.`,
    "",
    "=== YOUR TASK ===",
    "Plan the screens and interactions for this tutorial:",
    "",
    "1. Identify which app this involves (WeChat, Alipay, Taobao, etc.)",
    "2. Identify the app type (social-chat, payment, shopping, short-video, maps, food-delivery, etc.)",
    "3. For EACH step, describe exactly what the screen should look like:",
    "   - What page is this? (chat list, contact page, home page, settings, etc.)",
    "   - What is the ONE clickable element the user should tap?",
    "   - What element type is it? (tab, list-item, button, icon, avatar, menu-item, input-field)",
    "   - Describe the screen content: nav bar title, key list items, visible controls",
    "",
    "=== RETURN THIS EXACT JSON ===",
    "{",
    '  "appName": "App name in Chinese",',
    '  "appType": "social-chat|payment|shopping|short-video|maps|food-delivery|music|settings|other",',
    '  "accentColor": "#07C160",',
    '  "accentColor2": "#2DC100",',
    '  "backgroundColor": "#FFFFFF",',
    '  "navBarColor": "#EDEDED",',
    '  "tabBarColor": "#F7F7F7",',
    '  "screens": [',
    "    {",
    '      "step": 1,',
    '      "screenType": "chat-list|home|discover|profile|chat|search|pay|scan|product|map|settings|other",',
    '      "navTitle": "微信",',
    '      "bodyDescription": "Show a chat list with 5-6 contacts. Each has a circular avatar(40px), contact name, last message preview, and time. Include a search bar at top, and a 4-tab bar at bottom (微信, 通讯录, 发现, 我). Add notification badges on 2 tabs.",',
    '      "targetDescription": "Bottom tab bar icon labeled「通讯录」— this is the second tab from left",',
    '      "targetType": "tab",',
    '      "targetIndex": "tab-2",',
    '      "instruction": "请点一下屏幕底部的绿色「通讯录」按钮",',
    '      "elderTip": "这个按钮在手机最下面，左边第二个"',
    "    }",
    "  ]",
    "}",
    "",
    "=== RULES ===",
    "- Each screen should look like a COMPLETE app page, not a wireframe",
    "- ALL text must be in Chinese (matching real app text)",
    "- Colors should match the real app's identity",
    "- targetDescription must be specific enough that an AI can render it",
    "- bodyDescription must include enough detail to faithfully recreate the screen",
    "- tab bar descriptions should mention which tab is active/selected",
    "- Include realistic notification badges, unread counts, timestamps"
  ].join("\n");

  return { system, userContent: [{ type: "text", text: user }] };
}

// ── Stage 2: HTML Generation ──────────────────────────────────────

export function buildStage2Prompt({ goal, stage1Json, refImages }) {
  const plan = typeof stage1Json === "string" ? JSON.parse(stage1Json) : stage1Json;
  const stepCount = plan.screens?.length || 5;

  const system = [
    "You are a pixel-perfect HTML/CSS developer who builds interactive mobile app simulations.",
    "Your HTML pages TEACH elderly Chinese users how to operate smartphone apps step by step.",
    "Every page must look like a REAL app, not a tutorial mockup.",
    "Return ONLY valid JSON: {\"html\":\"...\",\"title\":\"...\",\"steps\":[...]}. No markdown fences."
  ].join(" ");

  const screensDesc = plan.screens.map((s, i) =>
    `  SCREEN ${i + 1}: "${s.navTitle}" (${s.screenType})\n` +
    `    Body: ${s.bodyDescription}\n` +
    `    TARGET → ${s.targetDescription} (${s.targetType})\n` +
    `    Instruction: ${s.instruction}`
  ).join("\n\n");

  const user = [
    `Build an interactive ${stepCount}-step tutorial HTML for: "${goal}"`,
    `App: ${plan.appName} (${plan.appType})`,
    `Accent color: ${plan.accentColor || "#07C160"}`,
    "",
    "=== SCREEN PLAN (from stage 1) ===",
    screensDesc,
    "",
    "=== HTML STRUCTURE (MUST FOLLOW EXACTLY) ===",
    "The HTML body contains a .phone container. Inside:",
    "- One <div class=\"page\" id=\"pageN\"> per screen (N=1,2,3...)",
    "- Only one page visible at a time: .page{display:none} then JS shows the active one",
    "- After the last page, a <div class=\"page\" id=\"completion\"> with a celebration message",
    "",
    "Each .page must contain exactly these elements in order:",
    "1. <div class=\"status-bar\">(9:41, signal icons)</div>",
    "2. <div class=\"nav-bar\">(realistic title matching the screen plan)</div>",
    "3. <div class=\"content\">(body layout matching the screen description)</div>",
    "4. If the screen has a bottom tab bar: <div class=\"tab-bar\">(tab icons + labels)</div>",
    "",
    "=== THE TARGET ELEMENT ===",
    "Each page has EXACTLY ONE clickable target. It must:",
    "- Be a NATIVE-LOOKING app element (tab, list item, button, icon, menu entry)",
    "- Have class=\"target\" + onclick=\"onTargetClick()\"",
    "- Use the app's accent color for active/selected state",
    "- Pulse gently: @keyframes pulse{0%,100%{box-shadow:0 0 0 0 rgba(ACCENT,.35)}50%{box-shadow:0 0 0 10px rgba(ACCENT,0)}}",
    "- Blend visually with the non-interactive elements around it",
    "",
    "=== DECORATIVE ELEMENTS (sell the realism) ===",
    "- Add 3-5 extra non-clickable items to each screen (other contacts, menu items, suggested content)",
    "- Use circles for avatars (background-color with Chinese initials), realistic names",
    "- Add notification badges (red dots or numbers in red circles #FA5151)",
    "- Include realistic timestamps (上午9:20, 昨天, 星期三, 6月15日)",
    "- Add dividers (1px solid #F0F0F0) between list items",
    "- Tab bar must show all icons with ONE highlighted as active matching the current page",
    "",
    "=== REQUIRED CSS (embed in <style>) ===",
    "*{margin:0;padding:0;box-sizing:border-box}",
    `body{font-family:-apple-system,'PingFang SC','Microsoft YaHei',sans-serif;background:#E5E5E5;display:flex;align-items:center;justify-content:center;min-height:100vh;padding:16px}`,
    `.phone{width:375px;min-height:680px;background:${plan.backgroundColor || '#FFFFFF'};border-radius:36px;overflow:hidden;box-shadow:0 20px 60px rgba(0,0,0,.25);position:relative;display:flex;flex-direction:column}`,
    ".page{width:100%;flex:1;display:none;flex-direction:column;overflow-y:auto}",
    ".page:first-of-type,#page1{display:flex}",
    `.status-bar{height:44px;background:#FFFFFF;display:flex;align-items:center;justify-content:space-between;padding:0 24px;font-size:13px;font-weight:600;flex-shrink:0;color:#000}`,
    `.nav-bar{height:44px;background:${plan.navBarColor || '#EDEDED'};display:flex;align-items:center;justify-content:center;font-size:17px;font-weight:500;color:#000;flex-shrink:0}`,
    ".content{flex:1;overflow-y:auto;display:flex;flex-direction:column}",
    `.tab-bar{height:56px;background:${plan.tabBarColor || '#F7F7F7'};border-top:0.5px solid #E6E6E6;display:flex;flex-shrink:0}`,
    ".tab-item{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;color:#999;font-size:11px}",
    ".tab-item.active{color:" + (plan.accentColor || "#07C160") + "}",
    "@keyframes pulse{0%,100%{box-shadow:0 0 0 0 " + (plan.accentColor || "#07C160") + "44}50%{box-shadow:0 0 0 10px " + (plan.accentColor || "#07C160") + "00}}",
    ".target{animation:pulse 2s infinite;cursor:pointer;transition:opacity 0.15s}",
    ".target:active{opacity:0.7}",
    "",
    "#completion{display:none;justify-content:center;align-items:center;text-align:center;flex-direction:column}",
    "#completion .emoji{font-size:72px;margin-bottom:16px}",
    "#completion .title{font-size:24px;font-weight:700;color:#000;margin-bottom:8px}",
    "#completion .sub{font-size:15px;color:#999}",
    "",
    "=== REQUIRED JS (embed in <script>) ===",
    "<script>",
    "var currentPage=0;var totalPages=" + stepCount + ";",
    "function onTargetClick(){",
    "  if(window.TargetBridge)window.TargetBridge.postMessage(JSON.stringify({event:'target_click',stepIndex:currentPage+1}));",
    "  document.getElementById('page'+(currentPage+1)).style.display='none';",
    "  currentPage++;",
    "  if(currentPage>=totalPages){document.getElementById('completion').style.display='flex';}",
    "  else{document.getElementById('page'+(currentPage+1)).style.display='flex';}",
    "}",
    "</script>",
    "",
    "=== STEPS ARRAY ===" + plan.screens.map((s, i) =>
      `"${i+1}: ${s.instruction || `请点击屏幕上的 ${s.targetDescription}`}"`
    ).join(", "),
    "",
    "Return: {\"html\":\"<!DOCTYPE html>\\\\n<html lang=\\\"zh-CN\\\">...\",\"title\":\"" + plan.appName + "\",\"steps\":[" + plan.screens.map(s =>
      `{"stepIndex":${s.step},"instruction":"${s.instruction || ''}","elderTip":"${s.elderTip || '慢慢来，不着急'}"}`
    ).join(",") + "]}"
  ];

  const userContent = [{ type: "text", text: user.join("\n") }];

  // Attach reference images
  if (refImages.length > 0) {
    userContent.push({
      type: "text",
      text: "=== VISUAL REFERENCE: These are real screenshots of " + plan.appName + ". Match the exact visual style, colors, layout, and typography. ==="
    });
    for (const ref of refImages) {
      userContent.push({
        type: "image_url",
        image_url: { url: `data:image/jpeg;base64,${ref.b64}` }
      });
    }
  }

  return { system, userContent };
}

// ── Unified export for single-call mode ────────────────────────────

export function buildChatGeneratePrompt({ goal, stepCount }) {
  // For single-call mode, we combine both stages into one prompt
  // This is simpler but less reliable than the two-stage pipeline
  const refs = getAllReferenceImages();

  const system = [
    "You are a mobile app tutorial builder for elderly Chinese users (60-80 years old).",
    "Create interactive multi-page HTML simulations of real smartphone apps.",
    "Return ONLY valid JSON: {\"html\":\"...\",\"title\":\"...\",\"steps\":[...]}. No markdown fences."
  ].join(" ");

  const user = [
    `Build a ${stepCount}-step tutorial for: "${goal}"`,
    "",
    "=== ESSENTIAL STRUCTURE ===",
    `${stepCount} separate .page divs + 1 completion page. Only one visible at a time.`,
    "Each page: status bar + nav bar + realistic body + optional tab bar + ONE clickable target.",
    "Target: a native-looking app element with class=\"target\" and onclick=\"proceed()\".",
    "proceed() advances to next page; on last page, shows completion screen.",
    "",
    "=== JS (include exactly) ===",
    "<script>var p=0;function onTargetClick(){if(window.TargetBridge)window.TargetBridge.postMessage(JSON.stringify({event:'target_click',stepIndex:p+1}));document.getElementById('page'+(p+1)).style.display='none';p++;if(p>=" + stepCount + "){document.getElementById('completion').style.display='flex'}else{document.getElementById('page'+(p+1)).style.display='flex'}}</script>",
    "",
    "=== DESIGN ===",
    "Identify which app this is and use its real design:",
    "- WeChat: green #07C160, #EDEDED nav bar, 4-tab bottom bar",
    "- Alipay: blue #1677FF, white bg, card layout, 5-tab bottom",
    "- Others: infer from app identity. Use the real app's accent color.",
    "",
    "Each page body should have 5-8 decorative items (contacts, list items, cards, menu entries)",
    "plus ONE target element. The target MUST blend in — it IS a real app element.",
    "Add realistic details: badges, timestamps, avatars with initials, dividers, unread counts.",
    "",
    "CSS: phone 375px wide, 36px radius, shadow, centered on #E5E5E5 bg. All text in proper containers. Flexbox only, no Grid.",
    "",
    "Return JSON with html string, title, and steps array (one instruction per step for elderly users)."
  ].join("\n");

  const userContent = [{ type: "text", text: user }];

  if (refs.length > 0) {
    userContent.push({ type: "text", text: "=== VISUAL REFERENCE (match this style) ===" });
    for (const ref of refs.slice(0, 2)) {
      userContent.push({ type: "image_url", image_url: { url: `data:image/jpeg;base64,${ref.b64}` } });
    }
  }

  return { system, userContent };
}
