const DATA_URL_PATTERN = /^data:image\/(png|jpeg|jpg|webp);base64,/i;
const DATA_VIDEO_URL_PATTERN = /^data:video\/(mp4|mpeg|quicktime|webm);base64,/i;

export function validateGenerateLessonRequest(body, config) {
  const frames = Array.isArray(body.frames) ? body.frames : null;
  if (!frames) {
    return { ok: false, statusCode: 400, message: "`frames` must be an array of base64 image data URLs." };
  }

  const sourceVideo = normalizeSourceVideo(body.sourceVideo);
  if (frames.length === 0 && !sourceVideo) {
    return { ok: false, statusCode: 400, message: "At least one frame or sourceVideo is required." };
  }

  if (frames.length > config.lessonMaxFrames) {
    return {
      ok: false,
      statusCode: 400,
      message: `Too many frames. Maximum is ${config.lessonMaxFrames}.`
    };
  }

  for (const [index, frame] of frames.entries()) {
    const image = normalizeFrameImage(frame);
    if (typeof image !== "string" || !DATA_URL_PATTERN.test(image)) {
      return {
        ok: false,
        statusCode: 400,
        message: `Frame ${index} must be a png, jpeg, or webp data URL.`
      };
    }

    const base64 = image.replace(DATA_URL_PATTERN, "");
    const estimatedBytes = Buffer.byteLength(base64, "base64");
    if (estimatedBytes > config.lessonMaxFrameBytes) {
      return {
        ok: false,
        statusCode: 413,
        message: `Frame ${index} is too large. Maximum is ${config.lessonMaxFrameBytes} bytes.`
      };
    }
  }

  return {
    ok: true,
    value: {
      frames: frames.map(normalizeFrame),
      sourceVideo,
      videoMeta: normalizeVideoMeta(body.videoMeta),
      audience: typeof body.audience === "string" ? body.audience.slice(0, 120) : "elderly smartphone user",
      goal: typeof body.goal === "string" ? body.goal.slice(0, 200) : "Explain the phone operation shown in the video."
    }
  };
}

function normalizeSourceVideo(sourceVideo) {
  if (!sourceVideo || typeof sourceVideo !== "object") {
    return undefined;
  }

  if (typeof sourceVideo.data !== "string" || !DATA_VIDEO_URL_PATTERN.test(sourceVideo.data)) {
    return undefined;
  }

  return {
    name: stringOrUndefined(sourceVideo.name, 180),
    type: stringOrUndefined(sourceVideo.type, 80),
    data: sourceVideo.data
  };
}

function normalizeFrame(frame, index) {
  if (typeof frame === "string") {
    return frame;
  }

  return {
    index: Number.isInteger(frame.index) ? frame.index : index,
    timeMs: finiteNumberOrUndefined(frame.timeMs),
    image: frame.image,
    touchCandidate: normalizeTouchCandidate(frame.touchCandidate)
  };
}

function normalizeFrameImage(frame) {
  return typeof frame === "string" ? frame : frame?.image;
}

function normalizeTouchCandidate(target) {
  if (!target || typeof target !== "object") {
    return undefined;
  }

  return {
    x: finiteNumberOrUndefined(target.x),
    y: finiteNumberOrUndefined(target.y),
    width: finiteNumberOrUndefined(target.width),
    height: finiteNumberOrUndefined(target.height),
    label: stringOrUndefined(target.label, 80)
  };
}

function normalizeVideoMeta(videoMeta) {
  if (!videoMeta || typeof videoMeta !== "object") {
    return {};
  }

  return {
    name: stringOrUndefined(videoMeta.name, 180),
    type: stringOrUndefined(videoMeta.type, 80),
    duration: finiteNumberOrUndefined(videoMeta.duration),
    width: finiteNumberOrUndefined(videoMeta.width),
    height: finiteNumberOrUndefined(videoMeta.height)
  };
}

function stringOrUndefined(value, maxLength) {
  return typeof value === "string" ? value.slice(0, maxLength) : undefined;
}

function finiteNumberOrUndefined(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}
