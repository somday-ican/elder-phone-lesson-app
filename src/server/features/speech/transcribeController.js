import { execFile } from "node:child_process";
import { readFile, writeFile, unlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { randomUUID } from "node:crypto";
import { readJsonBody } from "../../http/readJsonBody.js";
import { sendJson } from "../../http/sendJson.js";

const MAX_BYTES = 500000;
const WHISPER_BIN = "/Users/light/Library/Python/3.9/bin/whisper";

export async function transcribeController(req, res, config) {
  const body = await readJsonBody(req, MAX_BYTES);
  if (!body || typeof body.audio !== "string") {
    sendJson(res, 400, { error: "audio base64 string required." });
    return;
  }

  const match = body.audio.match(/^data:audio\/(wav|webm|mp3|m4a|ogg|x-wav);base64,(.+)$/);
  if (!match) {
    sendJson(res, 400, { error: "audio must be a base64 data URL (wav/webm/mp3/m4a/ogg)." });
    return;
  }

  const audioType = match[1];
  const extension = audioType === "x-wav" ? "wav" : audioType;
  const base64Data = match[2];
  const audioBytes = Buffer.from(base64Data, "base64");
  if (audioBytes.length < 200) {
    sendJson(res, 400, { error: "audio too short to transcribe." });
    return;
  }

  if (config.lessonGeneratorMode === "mock") {
    sendJson(res, 200, { text: "语音识别测试", meta: { generatorMode: "mock" } });
    return;
  }

  const uuid = randomUUID();
  const tmpPath = join(tmpdir(), `voice_${uuid}.${extension}`);
  const txtPath = join(tmpdir(), `voice_${uuid}.txt`);

  try {
    await writeFile(tmpPath, audioBytes);

    // Run whisper (tiny model, ~75MB download on first run, ~2-5s per transcription)
    await new Promise((resolve, reject) => {
      execFile(WHISPER_BIN, [
        tmpPath,
        "--model", "tiny",
        "--language", "zh",
        "--output_format", "txt",
        "--output_dir", tmpdir(),
      ], { timeout: 45000, maxBuffer: 1024 * 1024 }, (err) => {
        // whisper exits 0 even for warnings. Non-zero usually means missing ffmpeg or bad file.
        if (err) {
          reject(new Error(`Whisper failed: ${err.message}`));
          return;
        }
        resolve();
      });
    });

    // Read the output text file
    let text = "";
    try {
      text = (await readFile(txtPath, "utf8")).trim();
    } catch (_) {
      // No output = silent audio or model couldn't transcribe
    }

    sendJson(res, 200, { text, meta: { generatorMode: "whisper-tiny" } });
  } catch (error) {
    sendJson(res, 500, {
      error: "Transcription failed.",
      details: process.env.NODE_ENV !== "production" ? error.message : undefined
    });
  } finally {
    unlink(tmpPath).catch(() => {});
    unlink(txtPath).catch(() => {});
  }
}
