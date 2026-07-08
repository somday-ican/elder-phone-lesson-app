import { LESSON_SCHEMA_VERSION } from "../../../shared/lessonSchema.js";

export class MockLessonGenerator {
  async generate({ frames, videoMeta, goal }) {
    const now = new Date().toISOString();
    const stepCount = Math.min(Math.max(frames.length, 3), 5);
    const templates = [
      {
        title: "找到要操作的位置",
        instruction: "先看清屏幕上的主要按钮或输入框，确认要点击的位置。",
        type: "observe",
        target: { x: 0.5, y: 0.35, width: 0.5, height: 0.16, label: "主要操作区域" },
        elderTip: "不要着急，先把屏幕内容看清楚。"
      },
      {
        title: "轻点目标按钮",
        instruction: "用手指轻轻点一下高亮位置，等待手机进入下一步。",
        type: "tap",
        target: { x: 0.72, y: 0.78, width: 0.22, height: 0.1, label: "下一步按钮" },
        elderTip: "点击后等一两秒，不需要连续点很多次。"
      },
      {
        title: "检查页面变化",
        instruction: "确认页面已经切换，看看是否出现新的提示或确认按钮。",
        type: "wait",
        target: { x: 0.5, y: 0.5, width: 0.72, height: 0.38, label: "页面内容" },
        elderTip: "如果页面没反应，可以再轻点一次，不要用力按屏幕。"
      },
      {
        title: "完成确认",
        instruction: "看到确认、完成或保存按钮后，轻点它来结束本次操作。",
        type: "tap",
        target: { x: 0.5, y: 0.86, width: 0.42, height: 0.1, label: "确认按钮" },
        elderTip: "按钮通常在屏幕底部或右上角。"
      },
      {
        title: "回到安全页面",
        instruction: "操作结束后，确认结果已经保存，再返回上一页或关闭页面。",
        type: "observe",
        target: { x: 0.18, y: 0.08, width: 0.18, height: 0.1, label: "返回位置" },
        elderTip: "如果不确定是否完成，先不要退出，找家人确认也可以。"
      }
    ];

    return {
      schemaVersion: LESSON_SCHEMA_VERSION,
      id: `lesson_${Date.now()}`,
      title: "老人手机操作指导教程",
      summary: `根据 ${videoMeta.name || "上传视频"} 生成的模拟教程：${goal}`,
      createdAt: now,
      source: {
        type: "video_frames",
        frameCount: frames.length,
        generator: "mock"
      },
      steps: templates.slice(0, stepCount).map((template, index) => ({
        id: `step_${index + 1}`,
        order: index + 1,
        title: template.title,
        instruction: template.instruction,
        action: {
          type: template.type,
          target: template.target
        },
        frameIndex: Math.min(index, frames.length - 1),
        elderTip: template.elderTip
      }))
    };
  }
}
