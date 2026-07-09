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
    for (const f of readdirSync(REF_DIR).filter(isReferenceFile).sort())
      try {
        const ref = parseReferenceFile(f);
        const b64 = ref.textEncoded
          ? readFileSync(join(REF_DIR, f), "utf8").trim()
          : readFileSync(join(REF_DIR, f)).toString("base64");
        if (b64) {
          _refCache.push({
            name: ref.name,
            app: f.split('-')[0],
            mime: ref.mime,
            b64
          });
        }
      } catch (_) {}
  } catch (_) {}
  return _refCache;
}

function isReferenceFile(filename) {
  return /\.(txt|jpe?g|png|webp)$/i.test(filename);
}

function parseReferenceFile(filename) {
  const lower = filename.toLowerCase();
  if (lower.endsWith(".txt")) {
    return { name: filename.replace(/\.txt$/i, ""), mime: "image/jpeg", textEncoded: true };
  }
  if (lower.endsWith(".png")) {
    return { name: filename.replace(/\.png$/i, ""), mime: "image/png", textEncoded: false };
  }
  if (lower.endsWith(".webp")) {
    return { name: filename.replace(/\.webp$/i, ""), mime: "image/webp", textEncoded: false };
  }
  return { name: filename.replace(/\.jpe?g$/i, ""), mime: "image/jpeg", textEncoded: false };
}

function getReferenceImagesForApp(app) {
  const refs = getAllReferenceImages();
  const matched = refs.filter(ref => ref.app === app);
  return matched.length > 0 ? matched : refs.filter(ref => ref.app === "default");
}

function describeReference(ref) {
  const labels = {
    "wechat-chat-list": "WeChat chat list reference: top nav, search row, conversation cells, 44-48px avatars, timestamps, unread badges, thin dividers, bottom tab bar.",
    "wechat-discover": "WeChat Discover reference: white grouped list rows, green icons, compact spacing, thin dividers, bottom tab bar.",
    "wechat-step1-chat-list-to-discover": "Step 1 reference: WeChat chat list / main WeChat tab. Target is the bottom Discover tab.",
    "wechat-step2-discover-to-moments": "Step 2 reference: WeChat Discover page. Target is the Moments row.",
    "wechat-step3-moments-feed-camera": "Step 3 reference: WeChat Moments feed/profile feed. Target is the top-right camera publish button.",
    "wechat-step4-moments-action-sheet": "Step 4 reference: Moments publish action sheet. Target is '从手机相册选择'.",
    "wechat-step5-album-grid-select": "Step 5 reference: WeChat album picker grid. Target is selecting the first image thumbnail.",
    "wechat-step6-album-grid-done": "Step 6 reference: WeChat album picker with one selected item. Target is the bottom-right green '完成(1)' button.",
    "wechat-step7-moments-compose-publish": "Step 7 reference: Moments compose page with selected image. Target is adding text then tapping the top-right green '发表' button."
  };
  return labels[ref.name] || `${ref.name} visual reference: match spacing, typography, colors, tab bar and real app density.`;
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
  const refs = getReferenceImagesForApp(app);
  const hasCustomScreenshots = Array.isArray(customScreenshots) && customScreenshots.length > 0;
  const hasRefs = refs.length > 0;

  // When user provides screenshots, those are the PRIMARY reference.
  // Built-in references are supplementary (and labeled as such).
  const primaryRefMsg = hasCustomScreenshots
    ? "USER SCREENSHOTS PROVIDED BELOW. REPLICATE their EXACT visual style — colors, layout, spacing, typography, EVERYTHING."
    : (hasRefs ? `Built-in ${app} reference screenshots below. Use them as visual style references.` : "");

  const system = [
    "You are a master mobile UI developer. Create interactive HTML simulations of real apps for elderly Chinese users.",
    "Return ONLY valid JSON: {\"html\":\"<!DOCTYPE html>...\",\"title\":\"...\",\"steps\":[...]}. No markdown fences.",
    `Target app style: ${colors}`,
    `Steps: ${stepCount} screens (one .page div each, only page 1 visible; JS switches pages on click).`,
    hasCustomScreenshots ? "CRITICAL: User provided screenshots of the REAL app. Study them. Replicate the EXACT layout, colors, spacing, font sizes, card styles, EVERY detail." : "",
    hasRefs ? "Use reference images to match real app density, typography, navigation bars, tab bars, icons, dividers, avatar sizes and spacing. Do not create generic blue iOS mockups when a target app reference exists." : ""
  ].join(" ");

  const user = [
    `Build a ${stepCount}-page tutorial teaching an elderly person: "${goal}"`,
    `App style: ${colors}`,
    primaryRefMsg,
    "",
    "=== STRUCTURE ===",
    ".phone{375px,36px radius,nice shadow,centered on #E5E5E5}",
    "Inside .phone: status-bar{44px,9:41}+nav{44px}+.content{flex:1}+optional tab-bar",
    `${stepCount} .page divs + #completion. Only #page1 visible (display:flex), rest display:none.`,
    "",
    "=== CONTENT ===",
    "Each .page: 6-10 realistic elements (contacts,avatars,text,cards,icons,badges,timestamps,divider lines)",
    "+ EXACTLY ONE .target with onclick=\"onTargetClick(N)\" where N=1,2,3...",
    "Target IS a real app element — tab,list item,button,menu entry. NOT a tutorial label.",
    "Use real Chinese names, real message text, real timestamps (上午9:20,昨天,6月15日).",
    "Add red badges (#FA5151) and notification dots.",
    app === "wechat" ? "For WeChat: use #07C160 only for active tab/highlights; nav is light #EDEDED or white; list rows are 64-72px; avatars about 44-48px; bottom tabs are 微信/通讯录/发现/我; avoid fake gradient cards." : "",
    "",
    "=== JS (include exactly) ===",
    "<script>var p=0;function onTargetClick(n){if(window.TargetBridge)window.TargetBridge.postMessage(JSON.stringify({event:'target_click',stepIndex:n||(p+1)}));document.getElementById('page'+(p+1)).style.display='none';p++;if(p>="+stepCount+"){document.getElementById('completion').style.display='flex'}else{document.getElementById('page'+(p+1)).style.display='flex'}}</script>",
    "",
    "#completion: center big emoji + '完成了！' + subtitle",
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
    userContent.push({ type: "text", text: `=== BUILT-IN ${app.toUpperCase()} REFERENCE SCREENSHOTS ===\nStudy these images for visual style. Recreate similar UI patterns in HTML; do not mention the references to the user.` });
    for (const ref of refs) {
      userContent.push({ type: "text", text: describeReference(ref) });
      userContent.push({ type: "image_url", image_url: { url: `data:${ref.mime};base64,${ref.b64}` } });
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
