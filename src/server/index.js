import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { getConfig } from "./config.js";
import { sendJson } from "./http/sendJson.js";
import { generateLessonController } from "./features/video-to-lesson/generateLessonController.js";
import { analyzeButtonController } from "./features/button-analysis/analyzeButtonController.js";
import { generateUIController } from "./features/ui-generation/generateUIController.js";
import { chatGenerateController } from "./features/chat-generate/chatGenerateController.js";

const rootDir = fileURLToPath(new URL("../..", import.meta.url));
const publicDir = join(rootDir, "public");
const config = getConfig();

const mimeTypes = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml"
};

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host}`);

    if (req.method === "POST" && url.pathname === "/api/lessons/generate") {
      await generateLessonController(req, res, config);
      return;
    }

    if (req.method === "POST" && url.pathname === "/api/analyze-button") {
      await analyzeButtonController(req, res, config);
      return;
    }

    if (req.method === "POST" && url.pathname === "/api/generate-ui") {
      await generateUIController(req, res, config);
      return;
    }

    if (req.method === "POST" && url.pathname === "/api/chat-generate") {
      await chatGenerateController(req, res, config);
      return;
    }

    if (req.method === "POST" && url.pathname === "/api/lessons/generate-multimodal") {
      await generateLessonController(req, res, {
        ...config,
        lessonGeneratorMode: config.lessonGeneratorMode === "mock" ? "openai-compatible" : config.lessonGeneratorMode
      });
      return;
    }

    if (req.method === "GET") {
      await serveStatic(url.pathname, res);
      return;
    }

    sendJson(res, 404, { error: "Not found." });
  } catch (error) {
    const statusCode = error.statusCode || 500;
    sendJson(res, statusCode, {
      error: statusCode === 500 ? "Internal server error." : error.message,
      details: statusCode === 500 && process.env.NODE_ENV !== "production" ? error.message : undefined
    });
  }
});

server.listen(config.port, config.host, () => {
  console.log(`Dev server running at http://${config.host}:${config.port}`);
});

async function serveStatic(pathname, res) {
  const requestedPath = pathname === "/" ? "/index.html" : pathname;
  const safePath = normalize(decodeURIComponent(requestedPath)).replace(/^(\.\.[/\\])+/, "");
  const filePath = join(publicDir, safePath);

  if (!filePath.startsWith(publicDir)) {
    sendJson(res, 403, { error: "Forbidden." });
    return;
  }

  try {
    const fileStat = await stat(filePath);
    if (!fileStat.isFile()) {
      sendJson(res, 404, { error: "Not found." });
      return;
    }

    res.writeHead(200, {
      "content-type": mimeTypes[extname(filePath)] || "application/octet-stream",
      "content-length": fileStat.size
    });
    createReadStream(filePath).pipe(res);
  } catch {
    sendJson(res, 404, { error: "Not found." });
  }
}
