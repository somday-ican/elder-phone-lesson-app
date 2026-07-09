export function buildUIGenerationPrompt({ screenshots, markedPositions, goal }) {
  const system = [
    "You generate clean, minimal HTML pages that simulate mobile app screens.",
    "Return ONLY valid JSON with an \"html\" string field. No markdown fences.",
    "Keep the HTML under 3000 characters total.",
    "Use Chinese for all visible text."
  ].join(" ");

  const targets = markedPositions
    .map((_, i) => `  <button onclick="onTargetClick(${i + 1})" class="target">步骤${i + 1}</button>`)
    .join('\n');

  const user = [
    `Create a mobile-style HTML page based on this screenshot.`,
    goal ? `Use case: ${goal}` : '',
    ``,
    `REQUIREMENTS:`,
    `1. Phone frame (375px, centered, rounded corners, shadow)`,
    `2. Status bar "9:41" + nav bar with a title matching the screenshot`,
    `3. 3-5 list items or content sections inspired by the screenshot`,
    `4. Include these clickable target buttons exactly:`,
    targets,
    `5. Simple CSS: system fonts, white bg for phone, light gray page bg`,
    `6. Target buttons: blue bg, white text, rounded, with pulse animation`,
    ``,
    `Include this EXACT script:`,
    `<script>function onTargetClick(n){window.TargetBridge&&window.TargetBridge.postMessage(JSON.stringify({event:\"target_click\",stepIndex:n}))}</script>`,
    ``,
    `Return: {"html":"<!DOCTYPE html>\\n<html>...","title":"..."}`
  ].join('\n');

  return { system, user };
}
