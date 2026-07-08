const MAX_FRAMES = 8;
const JPEG_QUALITY = 0.72;

const state = {
  videoFile: null,
  frames: [],
  lesson: null,
  activeStepIndex: 0,
  playing: false,
  playTimer: null
};

const els = {
  videoInput: document.querySelector("#videoInput"),
  videoPreview: document.querySelector("#videoPreview"),
  extractButton: document.querySelector("#extractButton"),
  generateButton: document.querySelector("#generateButton"),
  framesGrid: document.querySelector("#framesGrid"),
  frameCount: document.querySelector("#frameCount"),
  statusBadge: document.querySelector("#statusBadge"),
  goalInput: document.querySelector("#goalInput"),
  activeFrame: document.querySelector("#activeFrame"),
  targetBox: document.querySelector("#targetBox"),
  lessonTitle: document.querySelector("#lessonTitle"),
  lessonSummary: document.querySelector("#lessonSummary"),
  stepCounter: document.querySelector("#stepCounter"),
  stepTitle: document.querySelector("#stepTitle"),
  stepInstruction: document.querySelector("#stepInstruction"),
  stepTip: document.querySelector("#stepTip"),
  stepsList: document.querySelector("#stepsList"),
  prevStepButton: document.querySelector("#prevStepButton"),
  nextStepButton: document.querySelector("#nextStepButton"),
  playButton: document.querySelector("#playButton")
};

els.videoInput.addEventListener("change", handleVideoSelected);
els.extractButton.addEventListener("click", extractFrames);
els.generateButton.addEventListener("click", generateLesson);
els.prevStepButton.addEventListener("click", () => showStep(state.activeStepIndex - 1));
els.nextStepButton.addEventListener("click", () => showStep(state.activeStepIndex + 1));
els.playButton.addEventListener("click", togglePlayback);

async function handleVideoSelected(event) {
  const [file] = event.target.files;
  if (!file) {
    return;
  }

  resetLesson();
  state.videoFile = file;
  state.frames = [];
  els.videoPreview.src = URL.createObjectURL(file);
  els.videoPreview.classList.add("has-video");
  els.extractButton.disabled = false;
  els.generateButton.disabled = true;
  setStatus("已选择视频");
  renderFrames();
}

async function extractFrames() {
  if (!state.videoFile) {
    return;
  }

  setStatus("正在抽帧");
  els.extractButton.disabled = true;
  els.generateButton.disabled = true;

  try {
    const frames = await captureVideoFrames(els.videoPreview, MAX_FRAMES);
    state.frames = frames;
    renderFrames();
    els.generateButton.disabled = frames.length === 0;
    setStatus(frames.length ? "已完成抽帧" : "未抽到帧");
  } catch (error) {
    setStatus(error.message || "抽帧失败");
  } finally {
    els.extractButton.disabled = false;
  }
}

async function captureVideoFrames(video, maxFrames) {
  await ensureVideoMetadata(video);

  const duration = Number.isFinite(video.duration) && video.duration > 0 ? video.duration : 1;
  const count = Math.min(maxFrames, Math.max(3, Math.ceil(duration / 2)));
  const canvas = document.createElement("canvas");
  const scale = Math.min(1, 720 / Math.max(video.videoWidth, video.videoHeight));
  canvas.width = Math.max(1, Math.round(video.videoWidth * scale));
  canvas.height = Math.max(1, Math.round(video.videoHeight * scale));
  const context = canvas.getContext("2d", { willReadFrequently: false });
  const frames = [];

  for (let index = 0; index < count; index += 1) {
    const time = count === 1 ? 0 : (duration * index) / (count - 1);
    await seekVideo(video, Math.min(Math.max(time, 0), Math.max(duration - 0.05, 0)));
    context.drawImage(video, 0, 0, canvas.width, canvas.height);
    frames.push({
      index,
      time,
      dataUrl: canvas.toDataURL("image/jpeg", JPEG_QUALITY)
    });
  }

  return frames;
}

function ensureVideoMetadata(video) {
  if (video.readyState >= 1) {
    return Promise.resolve();
  }

  return new Promise((resolve, reject) => {
    video.addEventListener("loadedmetadata", resolve, { once: true });
    video.addEventListener("error", () => reject(new Error("视频读取失败")), { once: true });
  });
}

function seekVideo(video, time) {
  return new Promise((resolve, reject) => {
    const cleanup = () => {
      video.removeEventListener("seeked", handleSeeked);
      video.removeEventListener("error", handleError);
    };
    const handleSeeked = () => {
      cleanup();
      resolve();
    };
    const handleError = () => {
      cleanup();
      reject(new Error("视频跳转失败"));
    };

    video.addEventListener("seeked", handleSeeked, { once: true });
    video.addEventListener("error", handleError, { once: true });
    video.currentTime = time;
  });
}

function renderFrames() {
  els.framesGrid.innerHTML = "";
  els.frameCount.textContent = `${state.frames.length} 帧`;

  for (const frame of state.frames) {
    const item = document.createElement("div");
    item.className = "frame-thumb";
    item.innerHTML = `<img src="${frame.dataUrl}" alt="第 ${frame.index + 1} 帧"><span>${frame.time.toFixed(1)}s</span>`;
    els.framesGrid.append(item);
  }
}

async function generateLesson() {
  if (state.frames.length === 0) {
    return;
  }

  setStatus("正在生成教程");
  els.generateButton.disabled = true;

  try {
    const response = await fetch("/api/lessons/generate", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        goal: els.goalInput.value,
        audience: "elderly smartphone user",
        videoMeta: {
          name: state.videoFile?.name,
          type: state.videoFile?.type,
          duration: els.videoPreview.duration,
          width: els.videoPreview.videoWidth,
          height: els.videoPreview.videoHeight
        },
        frames: state.frames.map((frame) => frame.dataUrl)
      })
    });

    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload.error || "生成失败");
    }

    state.lesson = payload.lesson;
    state.activeStepIndex = 0;
    renderLesson();
    setStatus("教程已生成");
  } catch (error) {
    setStatus(error.message || "生成失败");
  } finally {
    els.generateButton.disabled = false;
  }
}

function renderLesson() {
  const lesson = state.lesson;
  if (!lesson) {
    return;
  }

  els.lessonTitle.textContent = lesson.title;
  els.lessonSummary.textContent = lesson.summary;
  els.stepsList.innerHTML = "";

  for (const [index, step] of lesson.steps.entries()) {
    const li = document.createElement("li");
    li.textContent = `${step.order}. ${step.title}`;
    li.addEventListener("click", () => showStep(index));
    els.stepsList.append(li);
  }

  els.prevStepButton.disabled = false;
  els.nextStepButton.disabled = false;
  els.playButton.disabled = false;
  showStep(0);
}

function showStep(index) {
  const lesson = state.lesson;
  if (!lesson) {
    return;
  }

  const clampedIndex = Math.max(0, Math.min(index, lesson.steps.length - 1));
  state.activeStepIndex = clampedIndex;
  const step = lesson.steps[clampedIndex];
  const frame = state.frames[step.frameIndex] || state.frames[0];

  els.stepCounter.textContent = `${clampedIndex + 1} / ${lesson.steps.length}`;
  els.stepTitle.textContent = step.title;
  els.stepInstruction.textContent = step.instruction;
  els.stepTip.textContent = step.elderTip || "";
  els.activeFrame.src = frame.dataUrl;
  els.activeFrame.classList.add("has-frame");
  renderTargetBox(step.action?.target);

  Array.from(els.stepsList.children).forEach((item, itemIndex) => {
    item.classList.toggle("active", itemIndex === clampedIndex);
  });

  els.prevStepButton.disabled = clampedIndex === 0;
  els.nextStepButton.disabled = clampedIndex === lesson.steps.length - 1;
}

function renderTargetBox(target) {
  if (!target) {
    els.targetBox.hidden = true;
    return;
  }

  const imageRect = getRenderedImageRect(els.activeFrame);
  if (!imageRect.width || !imageRect.height) {
    requestAnimationFrame(() => renderTargetBox(target));
    return;
  }

  const width = target.width || 0.16;
  const height = target.height || 0.08;
  els.targetBox.hidden = false;
  els.targetBox.style.left = `${imageRect.left + (target.x - width / 2) * imageRect.width}px`;
  els.targetBox.style.top = `${imageRect.top + (target.y - height / 2) * imageRect.height}px`;
  els.targetBox.style.width = `${width * imageRect.width}px`;
  els.targetBox.style.height = `${height * imageRect.height}px`;
}

function getRenderedImageRect(image) {
  const containerRect = image.parentElement.getBoundingClientRect();
  const imageRect = image.getBoundingClientRect();
  return {
    left: imageRect.left - containerRect.left,
    top: imageRect.top - containerRect.top,
    width: imageRect.width,
    height: imageRect.height
  };
}

function togglePlayback() {
  if (state.playing) {
    stopPlayback();
    return;
  }

  state.playing = true;
  els.playButton.textContent = "暂停";
  state.playTimer = window.setInterval(() => {
    const nextIndex = state.activeStepIndex + 1;
    if (!state.lesson || nextIndex >= state.lesson.steps.length) {
      stopPlayback();
      return;
    }
    showStep(nextIndex);
  }, 2200);
}

function stopPlayback() {
  state.playing = false;
  els.playButton.textContent = "播放步骤";
  if (state.playTimer) {
    window.clearInterval(state.playTimer);
    state.playTimer = null;
  }
}

function resetLesson() {
  stopPlayback();
  state.lesson = null;
  state.activeStepIndex = 0;
  els.lessonTitle.textContent = "等待生成";
  els.lessonSummary.textContent = "上传视频并生成后，这里会显示操作教程。";
  els.stepCounter.textContent = "0 / 0";
  els.stepTitle.textContent = "暂无步骤";
  els.stepInstruction.textContent = "请选择视频开始。";
  els.stepTip.textContent = "";
  els.stepsList.innerHTML = "";
  els.activeFrame.removeAttribute("src");
  els.activeFrame.classList.remove("has-frame");
  els.targetBox.hidden = true;
  els.prevStepButton.disabled = true;
  els.nextStepButton.disabled = true;
  els.playButton.disabled = true;
}

function setStatus(text) {
  els.statusBadge.textContent = text;
}
