import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const REF_DIR = (() => {
  try { return join(dirname(fileURLToPath(import.meta.url)), "references"); }
  catch (_) { return join(import.meta.dirname ?? ".", "references"); }
})();

let _refCache = null;
function getAllReferenceImages() {
  if (_refCache) return _refCache;
  _refCache = [];
  try {
    for (const f of readdirSync(REF_DIR).filter(x => x.endsWith('.txt')))
      try { const b64 = readFileSync(join(REF_DIR, f), "utf8").trim(); if (b64) _refCache.push({ name: f.replace('.txt',''), b64 }); } catch (_) {}
  } catch (_) {}
  return _refCache;
}

// ── App design reference (compact) ──────────────────────────────

const APP_COLORS = {
  wechat:   'green #07C160,#EDEDED nav,4tab bar #F7F7F7,white bg,chat list',
  alipay:   'blue #1677FF,blue nav white title,white bg,icon grid,5tabs,#FF6600 amounts',
  taobao:   'orange #FF5000,#F5F5F5 bg,search bar,2col product cards,#FF5000 prices',
  meituan:  'yellow #FFD300,white nav,#F4F4F4 bg,food cards,#FFD300 order btn',
  douyin:   'pink #FE2C55,dark #000 bg,fullscreen video feed,dark profile',
  redbook:  'red #FF2442,white bg,waterfall 2col cards,5tabs',
  gaode:    'blue #0091FF,map bg,floating search,white bottom sheet',
  default:  'blue #007AFF,white bg,iOS-style nav,modern clean',
};

function detectApp(goal) {
  const g = goal.toLowerCase();
  if (g.includes('微信')||g.includes('wechat')||g.includes('朋友圈')||g.includes('视频')||g.includes('语音')) return 'wechat';
  if (g.includes('支付宝')||g.includes('扫码')||g.includes('付款')||g.includes('转账')) return 'alipay';
  if (g.includes('淘宝')||g.includes('购物')||g.includes('下单')||g.includes('快递')) return 'taobao';
  if (g.includes('美团')||g.includes('外卖')||g.includes('点餐')||g.includes('团购')) return 'meituan';
  if (g.includes('抖音')||g.includes('刷视频')||g.includes('看视频')) return 'douyin';
  if (g.includes('小红书')||g.includes('笔记')) return 'redbook';
  if (g.includes('高德')||g.includes('导航')||g.includes('地图')||g.includes('路线')) return 'gaode';
  return 'default';
}

// ── Main prompt builder ──────────────────────────────────────────

export function buildChatGeneratePrompt({ goal, stepCount, customScreenshots }) {
  const app = detectApp(goal);
  const colors = APP_COLORS[app] || APP_COLORS.default;
  const refs = getAllReferenceImages();
  const hasCustomScreenshots = Array.isArray(customScreenshots) && customScreenshots.length > 0;
  const hasRefs = refs.length > 0;

  // When user provides screenshots, those are the PRIMARY reference.
  // Built-in references are supplementary (and labeled as such).
  const primaryRefMsg = hasCustomScreenshots
    ? "USER SCREENSHOTS PROVIDED BELOW. REPLICATE their EXACT visual style — colors, layout, spacing, typography, EVERYTHING."
    : (hasRefs ? "Built-in reference screenshots below. Match their style if they match the target app." : "");

  const system = [
    "You are a master mobile UI developer. Create interactive HTML simulations of real apps for elderly Chinese users.",
    "Return ONLY valid JSON: {\"html\":\"<!DOCTYPE html>...\",\"title\":\"...\",\"steps\":[...]}. No markdown fences.",
    `Target app style: ${colors}`,
    `Steps: ${stepCount} screens (one .page div each, only page 1 visible; JS switches pages on click).`,
    hasCustomScreenshots ? "CRITICAL: User provided screenshots of the REAL app. Study them. Replicate the EXACT layout, colors, spacing, font sizes, card styles, EVERY detail." : ""
  ].join(" ");

  const user = [
    `Build a ${stepCount}-page tutorial teaching an elderly person: "${goal}"`,
    `App style: ${colors}`,
    "",
    "=== STRUCTURE ===",
    ".phone{375px,36px radius,nice shadow,centered on #E5E5E5}",
    "Inside .phone: status-bar{44px,9:41}+nav{44px}+.content{flex:1}+tab-bar{56px}",
    `${stepCount} .page divs + #completion. Only #page1 visible (display:flex), rest display:none.`,
    "",
    "=== BOTTOM TAB BAR (EVERY TUTORIAL PAGE) ===",
    "Each .page MUST end with a .tab-bar (56px height, flex row, 0.5px #E6E6E6 top border, bg matches app).",
    "Tab bar has 3-5 .tab-item divs (flex:1, centered, icon 22-24px + label 10px).",
    "One tab is .active (use app accent color). Others: color #999, decorative only, no onclick.",
    "#completion has NO tab bar — it's a full celebration screen.",
    "",
    "=== CONTENT ===",
    "Each .page: 6-10 realistic elements (contacts,avatars,text,cards,icons,badges,timestamps,divider lines)",
    "+ EXACTLY ONE .target with onclick=\"onTargetClick(N)\" where N=1,2,3...",
    "+ .tab-bar at bottom (decorative, NOT the target).",
    "Target IS a real app element — tab,list item,button,menu entry. NOT a tutorial label.",
    "Use real Chinese names, real message text, real timestamps (上午9:20,昨天,6月15日).",
    "Add red badges (#FA5151) and notification dots.",
    "",
    "=== COMPLETION PAGE (ACHIEVEMENT STYLE) ===",
    "#completion: display:none, flex-direction:column, background:#F9F8F6, align-items:center, justify-content:center, min-height:100%",
    "Inside #completion:",
    "- 64px trophy/star emoji with CSS filter:drop-shadow(0 0 12px rgba(255,107,53,0.2))",
    '- Title: font-size 30px, font-weight 800, color #000, margin 16px 0 8px, text "完成了！"',
    '- Subtitle: font-size 16px, color #999, text "你学会"' + goal + '"了"',
    "- 2-3 achievement cards (white bg, border-radius 20px, padding 20px, shadow, margin 12px 0, width 80%):",
    "  each card: flex row, icon left (32px orange), number right (24px bold), label below",
    '- Cards: "完成步骤"=' + stepCount + ', "准确率" (random 80-100%), "学习用时" (short time)',
    "- Orange accent #FF6B35 for icons and highlights",
    "- NO tab bar, NO status bar on completion — immersion mode",
    "",
    "=== JS (include exactly) ===",
    "<script>var p=0;function onTargetClick(n){if(window.TargetBridge)window.TargetBridge.postMessage(JSON.stringify({event:'target_click',stepIndex:n||(p+1)}));document.getElementById('page'+(p+1)).style.display='none';p++;if(p>="+stepCount+"){document.getElementById('completion').style.display='flex'}else{document.getElementById('page'+(p+1)).style.display='flex'}}</script>",
    "",
    ".target: pulse animation 2s, cursor:pointer. @keyframes pulse{0%,100%{box-shadow:0 0 0 0 VAR}50%{box-shadow:0 0 0 12px VAR00}}",
    "",
    `Return: {"html":"<!DOCTYPE html>\\n<html lang=\\"zh-CN\\">...","title":"...","steps":${stepCount} items with stepIndex,instruction,elderTip}`,
  ];

  const userContent = [{ type: "text", text: user.join("\n") }];

  // User-provided screenshots = PRIMARY reference (highest priority)
  if (hasCustomScreenshots) {
    userContent.push({ type: "text", text: "=== YOUR SCREENSHOTS (REPLICATE EXACTLY) ===" });
    for (const b64 of customScreenshots) {
      userContent.push({ type: "image_url", image_url: { url: b64 } });
    }
  }
  // Built-in references = supplementary (only if no custom screenshots, or as side help)
  else if (hasRefs) {
    userContent.push({ type: "text", text: "=== REFERENCE SCREENSHOTS (match style if target app matches) ===" });
    for (const ref of refs) {
      userContent.push({ type: "image_url", image_url: { url: `data:image/jpeg;base64,${ref.b64}` } });
    }
  }

  return { system, userContent };
}

// ── Stage 1 & 2 (for future pipeline) ───────────────────────────

export function buildStage1Prompt({ goal, stepCount }) {
  return {
    system: "Plan app tutorial screens. Return JSON.",
    userContent: [{ type: "text", text: [
      `Plan ${stepCount} screens for: "${goal}"`,
      `App: ${APP_COLORS[detectApp(goal)]}`,
      "Return: {\"appName\":\"\",\"accentColor\":\"\",\"screens\":[{step,screenType,navTitle,bodyDescription,targetDescription,targetType,instruction,elderTip}]}"
    ].join("\n") }]
  };
}

export function buildStage2Prompt({ goal, stage1Json }) {
  const plan = typeof stage1Json === "string" ? JSON.parse(stage1Json) : stage1Json;
  const stepCount = (plan.screens || []).length || 5;
  return buildChatGeneratePrompt({ goal, stepCount }); // reuse main builder
}
