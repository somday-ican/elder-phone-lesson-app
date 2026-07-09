export function buildChatGeneratePrompt({ goal, stepCount }) {
  const system = [
    "You are an expert mobile UI developer who creates realistic Chinese app simulation pages.",
    "You understand elderly users who are learning to use smartphones.",
    "Every UI you generate should use real Chinese text, real app layouts, and real app colors.",
    "Return ONLY valid JSON: {\"html\": \"...\", \"title\": \"...\", \"steps\": [...]}.",
    "No markdown fences. The html string must be a complete standalone HTML document."
  ].join(" ");

  const user = [
    `An elderly Chinese person wants to learn: "${goal}"`,
    "",
    "Generate a realistic mobile app simulation HTML page that teaches this step by step.",
    `Create exactly ${stepCount} clickable steps.`,
    "",
    "=== HTML PAGE REQUIREMENTS ===",
    "1. Phone frame: 375px wide, centered, rounded corners, shadow, on gray background",
    "2. Status bar (9:41) + navigation bar with a realistic Chinese title matching the scenario",
    "3. Body content that looks like a REAL app — list items, chat bubbles, buttons, tabs, text,",
    "   avatars, whatever the actual app would show. Study WeChat/Weixin design patterns:",
    "   green (#07C160 or #2DC100) is WeChat's accent color, use it for WeChat-related UIs",
    "4. For EACH of the ${stepCount} steps, create exactly ONE visible clickable button with:",
    "   - onclick=\"onTargetClick(N)\" where N is 1,2,3... in order",
    "   - The exact text the user should see on that button",
    "   - The button's realistic background color from the app being simulated",
    "   - Large touch target (44px+), subtle pulse animation",
    "   - The button must look like part of the REAL app interface, not a tutorial overlay",
    "",
    "=== JS BRIDGE (MUST INCLUDE exactly this script) ===",
    "<script>function onTargetClick(n){if(window.TargetBridge)window.TargetBridge.postMessage(JSON.stringify({event:'target_click',stepIndex:n}))}</script>",
    "",
    "=== STEPS ARRAY ===",
    "For each step, write a short instruction an elderly person can understand:",
    "- instruction: one sentence in Chinese, large-font friendly, like '请点一下绿色的「视频通话」按钮'",
    "- elderTip: safety or reassurance tip, like '如果不小心点错了也没关系，可以重新来'",
    "",
    "Return this exact JSON:",
    "{",
    '  "html": "<!DOCTYPE html>\\n<html lang=\\"zh-CN\\">...full page...</html>",',
    '  "title": "微信视频通话",',
    '  "steps": [',
    '    {"stepIndex": 1, "instruction": "请点一下...", "elderTip": "..."},',
    '    {"stepIndex": 2, "instruction": "请点一下...", "elderTip": "..."}',
    "  ]",
    "}",
    "",
    "Make the HTML look REAL. A social app should look like a social app.",
    "A shopping app should look like a shopping app. Study design patterns carefully."
  ].join("\n");

  return { system, user };
}
