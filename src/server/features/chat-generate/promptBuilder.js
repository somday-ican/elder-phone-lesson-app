import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const REF_DIR = (() => {
  try { return join(dirname(fileURLToPath(import.meta.url)), "references"); }
  catch (_) { return join(import.meta.dirname ?? ".", "references"); }
})();

let _refCache = null;
function getReferenceImages() {
  if (_refCache) return _refCache;
  _refCache = [];
  for (const name of ["wechat-chat-list", "wechat-discover"]) {
    try {
      const b64 = readFileSync(join(REF_DIR, `${name}.txt`), "utf8").trim();
      if (b64) _refCache.push({ name, b64 });
    } catch (_) {}
  }
  return _refCache;
}

export function buildChatGeneratePrompt({ goal, stepCount }) {
  const refs = getReferenceImages();

  const system = [
    "You are a mobile UI expert who builds interactive step-by-step tutorial simulations.",
    "Your HTML pages are used to TEACH elderly Chinese users how to operate smartphone apps.",
    "Every page must look like a REAL app (WeChat/微信), with each step feeling like a natural action.",
    "Return ONLY valid JSON: {\"html\":\"...\",\"title\":\"...\",\"steps\":[...]}. No markdown fences.",
    "CRITICAL: The HTML must simulate MULTIPLE PAGES (one per step). Each step the user sees a new screen."
  ].join("\n");

  const userParts = [
    `Task: Create an interactive tutorial HTML for: "${goal}"`,
    `Steps: ${stepCount} distinct actions the user will take.`,
    "",
    "=== CRITICAL: MULTI-PAGE SIMULATION ===",
    `Create ${stepCount} separate "pages" (div.page elements) in the HTML.`,
    "ONLY one page is visible at a time (use display:none/display:flex).",
    "Each page represents one step in the tutorial:",
    "- Page 1 (step 1): The STARTING screen. Shows 1 clickable target blended into the app UI.",
    "- Page 2 (step 2): The NEXT screen after step 1. Shows a NEW clickable target.",
    "- ...and so on for all ${stepCount} steps.",
    "Navigation: when user clicks the target on page N, HIDE page N and SHOW page N+1.",
    `When user clicks the target on page ${stepCount} (final step), show a completion page.`,
    "",
    "=== HOW TO SWITCH PAGES ===",
    "Each target button MUST use this onclick:",
    "onclick=\"onTargetClick(N);switchPage(N)\"",
    "AND include this function in <script>:",
    "function switchPage(step){document.querySelectorAll('.page').forEach(function(p,i){p.style.display=(i===step)?'flex':'none'});if(document.getElementById('progress'))document.getElementById('progress').textContent=step;if(step>=" + stepCount + "){document.getElementById('completion').style.display='flex';document.body.className='completed';}}",
    "",
    "=== EACH PAGE MUST CONTAIN ===",
    "- Status bar (9:41, signal icons)",
    "- Navigation bar with a realistic title matching the step context",
    "- Body content that looks like a REAL WeChat screen (chat list, contact info, menu, chat window, etc.)",
    "- EXACTLY ONE clickable target (onclick=\"onTargetClick(N);switchPage(N)\") that blends naturally into the UI",
    "- The target should look like a NATIVE app element — a chat item, a tab, a button, a contact, a menu item",
    "- DECORATIVE elements: other items, text, avatars, dividers, badges to fill out the screen realistically",
    "",
    "=== WECHAT DESIGN SPEC ===",
    "Nav bar: #EDEDED bg, 44px, title #000 17px weight 500, NOT bold",
    "Accent: #07C160 (WeChat green) for buttons, switches, active tabs",
    "Tab bar: #F7F7F7 bg, 0.5px #E6E6E6 top border, 56px height",
    "Tabs: 4 icons — 微信💬 通讯录👤 发现🔍 我🙂, inactive #999, active #07C160",
    "Chat items: 40px circle avatar, 16px title #000, 13px subtitle #999, 12px time #B2B2B2",
    "List dividers: 1px #F0F0F0, left-indent 68px",
    "Search bar: #EDEDED bg, 6px radius, 36px height",
    "Font: -apple-system,'PingFang SC','Microsoft YaHei',sans-serif",
    "",
    "=== CSS REQUIREMENTS ===",
    "*{margin:0;padding:0;box-sizing:border-box}",
    "body{font-family:-apple-system,'PingFang SC','Microsoft YaHei',sans-serif;background:#E5E5E5;display:flex;align-items:center;justify-content:center;min-height:100vh}",
    ".phone{width:375px;height:700px;background:#fff;border-radius:36px;overflow:hidden;box-shadow:0 20px 60px rgba(0,0,0,.25);position:relative}",
    ".page{width:100%;height:100%;display:none;flex-direction:column;background:#fff;overflow-y:auto}",
    ".page:first-of-type{display:flex}",
    ".status-bar{height:44px;background:#fff;display:flex;align-items:center;justify-content:space-between;padding:0 24px;font-size:13px;font-weight:600}",
    ".nav-bar{height:44px;background:#EDEDED;display:flex;align-items:center;justify-content:center;font-size:17px;font-weight:500;color:#000;flex-shrink:0}",
    ".content{flex:1;overflow-y:auto;display:flex;flex-direction:column}",
    "",
    "=== TARGET STYLING ===",
    "Target button/element should pulse gently: @keyframes pulse{0%,100%{box-shadow:0 0 0 0 rgba(7,193,96,.4)}50%{box-shadow:0 0 0 8px rgba(7,193,96,0)}}.target{animation:pulse 2s infinite;cursor:pointer}",
    "",
    "=== COMPLETION PAGE ===",
    '<div id="completion" class="page" style="display:none;justify-content:center;align-items:center;text-align:center">',
    '<div><div style="font-size:64px;margin-bottom:16px">🎉</div>',
    '<div style="font-size:22px;font-weight:700;color:#000;margin-bottom:8px">完成了！</div>',
    '<div style="font-size:15px;color:#999">你学会「' + goal + '」了</div></div></div>',
    "",
    "=== JS BRIDGE (INCLUDE EXACTLY) ===",
    "<script>function onTargetClick(n){if(window.TargetBridge)window.TargetBridge.postMessage(JSON.stringify({event:'target_click',stepIndex:n}))};function switchPage(s){document.querySelectorAll('.page').forEach(function(p,i){p.style.display=(i===s)?'flex':'none'});var el=document.getElementById('progress');if(el)el.textContent=s;if(s>=" + stepCount + "){var c=document.getElementById('completion');if(c)c.style.display='flex'}}</script>",
    "",
    "=== STEPS ARRAY ===",
    "For each step, write one sentence for a 70-year-old:",
    '- instruction: "请点一下绿色的「通讯录」按钮"',
    '- elderTip: "点错了也没关系，重新来就好"',
    "",
    `Return JSON: {"html":"<!DOCTYPE html>\\n<html lang=\\"zh-CN\\">...","title":"...","steps":[...]}`,
  ];

  const userContent = [{ type: "text", text: userParts.join("\n") }];

  if (refs.length > 0) {
    userContent.push({ type: "text", text: "=== STYLE REFERENCE: Match this WeChat look ===" });
    for (const ref of refs) {
      userContent.push({ type: "image_url", image_url: { url: `data:image/jpeg;base64,${ref.b64}` } });
    }
  }

  return { system, userContent };
}
