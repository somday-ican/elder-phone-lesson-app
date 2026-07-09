export function buildUIGenerationPrompt({ screenshots, markedPositions, goal }) {
  const marksInfo = markedPositions
    .map((m, i) => `  Step ${i + 1}: position (${m.x.toFixed(2)}, ${m.y.toFixed(2)}) on screenshot ${i + 1}`)
    .join('\n');

  const system = [
    "You are an expert mobile UI developer who creates pixel-perfect HTML replicas of app screenshots.",
    "You write clean, production-quality HTML/CSS/JS that faithfully reproduces mobile app interfaces.",
    "ALL text and labels MUST be in Chinese.",
    "Return ONLY valid JSON: {\"html\": \"...\", \"title\": \"...\"}. No markdown fences."
  ].join(" ");

  const user = [
    `I will show you ${screenshots.length} screenshots from a mobile app.`,
    goal ? `Context: ${goal}` : '',
    '',
    'The user marked these positions as buttons for an elderly person to click:',
    marksInfo,
    '',
    'Create a standalone HTML page that looks like the first screenshot.',
    'Make it look like a REAL phone screen — not wireframes, not just buttons.',
    '',
    'MUST include:',
    '- Phone frame: 375px wide, rounded, shadow, centered on gray bg',
    '- Status bar + navigation bar with the actual title from the screenshot',
    '- Body content matching the screenshot: list items, avatars, text, icons, tabs, etc.',
    '- Real colors, real text, real layout from the screenshot',
    '',
    'For EACH marked position, add a target button:',
    '- onclick="onTargetClick(stepIndex)" (1,2,3...)',
    '- Large (44px+), with subtle pulse animation',
    '- Button text must match what\'s actually on that button in the screenshot',
    '- Blend naturally into the page layout',
    '',
    'Use system fonts, flexbox layout, inline CSS.',
    '',
    'Include this JS at the bottom:',
    '<script>function onTargetClick(n){if(window.TargetBridge)window.TargetBridge.postMessage(JSON.stringify({event:"target_click",stepIndex:n}))}</script>',
    '',
    'Return: {"html":"<!DOCTYPE html>\\n<html>...","title":"..."}'
  ].join('\n');

  return { system, user };
}
