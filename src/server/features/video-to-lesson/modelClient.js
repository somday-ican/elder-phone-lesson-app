export class ModelClient {
  constructor({ mode, baseUrl, modelName, apiKey }) {
    this.mode = mode;
    this.baseUrl = normalizeBaseUrl(baseUrl);
    this.modelName = modelName;
    this.apiKey = apiKey;
  }

  async generate({ frames, sourceVideo, frameSelection, videoMeta, audience, goal, prompt }) {
    if (!this.baseUrl || !this.modelName || !this.apiKey) {
      throw new Error("AI_BASE_URL, AI_MODEL_NAME, and AI_API_KEY are required for remote generation.");
    }

    const response = await fetch(`${this.baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${this.apiKey}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({
        model: this.modelName,
        temperature: 0.2,
        response_format: { type: "json_object" },
        messages: [
          {
            role: "system",
            content: prompt?.system || buildSystemPrompt()
          },
          {
            role: "user",
            content: buildUserContent({ frames, sourceVideo, frameSelection, videoMeta, audience, goal, prompt })
          }
        ]
      })
    });

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(`Model request failed: ${response.status} ${JSON.stringify(payload)}`);
    }

    const content = payload.choices?.[0]?.message?.content;
    if (!content) {
      throw new Error("Model response did not include choices[0].message.content.");
    }

    const parsed = typeof content === "string" ? JSON.parse(stripJsonFence(content)) : content;
    return parsed.lesson || parsed;
  }
}

function buildSystemPrompt() {
  return [
    "You generate step-by-step smartphone operation lessons for elderly users.",
    "Return strict JSON only.",
    "Use relative coordinates from 0 to 1 for every action target."
  ].join(" ");
}

function buildUserContent({ frames, sourceVideo, frameSelection, videoMeta, audience, goal, prompt }) {
  const text = [
    "Analyze this smartphone operation recording from the sampled frame sequence and generate an elderly-friendly tutorial.",
    "Use the image frames as a chronological sequence from one screen recording.",
    "The screen may contain many static white circles or buttons. Do not treat every white circle as a touch point.",
    "A real touch indicator is usually a transient semi-transparent dot/ripple that appears, moves, or disappears between nearby frames.",
    "Compare adjacent frames and prefer locations that changed over time.",
    "If touchCandidate exists, use it as a strong temporal-difference hint, but verify it against the visual frame sequence.",
    "Only create tutorial steps for meaningful user actions, not every provided frame.",
    "Merge repeated frames or repeated touch candidates into one step.",
    "Use frameIndex values from the original frame indexes shown before each image.",
    `Original extracted frame count: ${frameSelection?.originalFrameCount ?? frames.length}`,
    `Sent original frame indexes: ${JSON.stringify(frameSelection?.sentFrameIndexes || frames.map((frame, index) => getFrameIndex(frame, index)))}`,
    "Return JSON with exactly this top-level shape: { \"lesson\": { ... } }.",
    "Action type must be one of: tap, long_press, swipe, type, wait, observe.",
    "Coordinates must be relative 0..1. x and y are the center of the target.",
    `Goal: ${goal}`,
    `Audience: ${audience}`,
    `Video meta: ${JSON.stringify(videoMeta || {})}`,
    `Prompt preview: ${JSON.stringify(prompt?.user || {})}`,
    `Frame touch candidates from local temporal differencing: ${JSON.stringify(frames.map(toFrameHint))}`,
    `Required lesson example: ${JSON.stringify(buildLessonExample(frames.length))}`
  ].join("\n\n");

  return [
    { type: "text", text },
    ...frames.flatMap((frame, index) => [
      {
        type: "text",
        text: `Frame ${getFrameIndex(frame, index)} at ${getFrameTimeMs(frame) ?? "unknown"} ms. Touch candidate: ${JSON.stringify(getFrameTouchCandidate(frame) || null)}`
      },
      {
        type: "image_url",
        image_url: {
          url: getFrameImage(frame)
        }
      }
    ])
  ];
}

function buildLessonExample(frameCount) {
  return {
    lesson: {
      schemaVersion: "1.0.0",
      id: "lesson_generated_id",
      title: "老人手机操作指导教程",
      summary: "short summary",
      createdAt: new Date().toISOString(),
      source: {
        type: "video_frames",
        frameCount,
        generator: "multimodal"
      },
      steps: [
        {
          id: "step_1",
          order: 1,
          title: "step title",
          instruction: "elderly-friendly instruction",
          action: {
            type: "tap",
            target: {
              x: 0.5,
              y: 0.5,
              width: 0.18,
              height: 0.09,
              label: "button label"
            }
          },
          frameIndex: 0,
          elderTip: "short safety tip"
        }
      ]
    }
  };
}

function getFrameImage(frame) {
  return typeof frame === "string" ? frame : frame.image;
}

function getFrameIndex(frame, fallback) {
  return typeof frame === "string" ? fallback : frame.index;
}

function getFrameTimeMs(frame) {
  return typeof frame === "string" ? undefined : frame.timeMs;
}

function getFrameTouchCandidate(frame) {
  return typeof frame === "string" ? undefined : frame.touchCandidate;
}

function toFrameHint(frame, index) {
  if (typeof frame === "string") {
    return { index, touchCandidate: null };
  }

  return {
    index: frame.index,
    timeMs: frame.timeMs,
    touchCandidate: frame.touchCandidate || null
  };
}

function stripJsonFence(value) {
  return value.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
}

function normalizeBaseUrl(baseUrl) {
  if (!baseUrl) {
    return "";
  }

  return baseUrl.replace(/\/+$/, "").replace(/\/chat\/completions$/, "");
}
