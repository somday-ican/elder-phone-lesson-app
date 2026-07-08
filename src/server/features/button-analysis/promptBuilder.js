export function buildButtonAnalysisPrompt({ screenshot, markedPosition, goal }) {
  const system = [
    "You are a precise UI element analyzer. Your task is to identify buttons and controls in mobile app screenshots.",
    "Given a screenshot and a marked position (relative coordinates 0..1), identify the exact button or clickable element at that position.",
    "Return ONLY valid JSON matching the specified schema. No markdown, no explanation.",
    "All coordinates are relative (0..1) where (0,0) is top-left and (1,1) is bottom-right.",
    "Be precise about bounding boxes — look at the actual pixel boundaries of the button, not a rough guess.",
    "Extract the button's visual style from the screenshot: background color, text color, border radius, font weight."
  ].join(" ");

  const user = [
    "Analyze this mobile app screenshot.",
    `The user marked a position at relative coordinates (${markedPosition.x.toFixed(3)}, ${markedPosition.y.toFixed(3)}).`,
    "",
    "Identify the EXACT button or clickable element at or nearest to this position:",
    "1. Find the precise bounding box of the button (not just a rough area — look at the button's actual edges)",
    "2. Read the exact text on the button",
    "3. Extract the button's visual style from the screenshot: background color (hex), text color (hex), border radius, font size, font weight",
    "4. Describe what this button does (its function in the app)",
    "",
    goal ? `Context — the user wants to: ${goal}` : "",
    "",
    "Return this exact JSON shape:",
    "{",
    "  \"boundingBox\": {",
    "    \"x\": 0.0, \"y\": 0.0,",
    "    \"width\": 0.0, \"height\": 0.0",
    "  },",
    "  \"label\": \"按钮上的文字\",",
    "  \"actionDescription\": \"这个按钮的功能描述\",",
    "  \"instruction\": \"面向老年人的操作提示（一句话）\",",
    "  \"elderTip\": \"额外的安全提示或注意事项\",",
    "  \"buttonStyle\": {",
    "    \"backgroundColor\": \"#07C160\",",
    "    \"textColor\": \"#FFFFFF\",",
    "    \"borderRadius\": 8,",
    "    \"fontSize\": 16,",
    "    \"fontWeight\": \"normal\"",
    "  }",
    "}",
    "",
    "IMPORTANT:",
    "- x,y in boundingBox is the CENTER of the button (not top-left corner)",
    "- width,height are the button's full dimensions",
    "- All 4 boundingBox values are relative 0..1",
    "- label must be the EXACT text shown on the button (in Chinese if that's what's shown)",
    "- instruction should be simple enough for an elderly person to understand",
    "- buttonStyle values should be extracted by visually inspecting the screenshot — be accurate"
  ].filter(Boolean).join("\n");

  return { system, user };
}

export function buildButtonAnalysisExample() {
  return {
    boundingBox: { x: 0.35, y: 0.78, width: 0.14, height: 0.06 },
    label: "下一步",
    actionDescription: "点击后进入下一个页面",
    instruction: "请点击屏幕下方的蓝色「下一步」按钮",
    elderTip: "按钮在屏幕下方中间位置，比较大，容易找到",
    buttonStyle: {
      backgroundColor: "#007AFF",
      textColor: "#FFFFFF",
      borderRadius: 10,
      fontSize: 17,
      fontWeight: "bold"
    }
  };
}
