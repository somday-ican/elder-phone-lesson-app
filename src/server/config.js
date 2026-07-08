import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

loadEnvFile(".env.local");

const DEFAULTS = {
  HOST: "127.0.0.1",
  PORT: "3000",
  LESSON_MAX_FRAMES: "24",
  LESSON_MAX_FRAME_BYTES: "500000",
  LESSON_MAX_REQUEST_BYTES: "7000000",
  LESSON_GENERATOR_MODE: "mock",
  AI_BASE_URL: "",
  AI_MODEL_NAME: "",
  AI_API_KEY: ""
};

function loadEnvFile(filename) {
  const filePath = join(process.cwd(), filename);
  if (!existsSync(filePath)) {
    return;
  }

  const lines = readFileSync(filePath, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }

    const separatorIndex = trimmed.indexOf("=");
    if (separatorIndex === -1) {
      continue;
    }

    const key = trimmed.slice(0, separatorIndex).trim();
    const value = trimmed.slice(separatorIndex + 1).trim().replace(/^["']|["']$/g, "");
    if (key && process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
}

export function getConfig(env = process.env) {
  return {
    host: env.HOST || DEFAULTS.HOST,
    port: parseInteger(env.PORT, DEFAULTS.PORT),
    lessonMaxFrames: parseInteger(env.LESSON_MAX_FRAMES, DEFAULTS.LESSON_MAX_FRAMES),
    lessonMaxFrameBytes: parseInteger(env.LESSON_MAX_FRAME_BYTES, DEFAULTS.LESSON_MAX_FRAME_BYTES),
    lessonMaxRequestBytes: parseInteger(env.LESSON_MAX_REQUEST_BYTES, DEFAULTS.LESSON_MAX_REQUEST_BYTES),
    lessonGeneratorMode: env.LESSON_GENERATOR_MODE || DEFAULTS.LESSON_GENERATOR_MODE,
    aiBaseUrl: env.AI_BASE_URL || env.OMINIGATE_BASE_URL || DEFAULTS.AI_BASE_URL,
    aiModelName: env.AI_MODEL_NAME || DEFAULTS.AI_MODEL_NAME,
    aiApiKey: env.AI_API_KEY || env.OMINIGATE_API_KEY || DEFAULTS.AI_API_KEY
  };
}

function parseInteger(value, fallback) {
  const parsed = Number.parseInt(value || fallback, 10);
  return Number.isFinite(parsed) ? parsed : Number.parseInt(fallback, 10);
}
