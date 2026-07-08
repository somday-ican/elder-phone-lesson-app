import '../models/button_analysis.dart';
import '../models/lesson.dart';
import '../models/ui_description.dart';
import '../models/video_frame.dart';
import 'model_client.dart';
import 'prompt_builder.dart';

class MockLessonGenerator implements ModelClient {
  const MockLessonGenerator();

  @override
  bool get supportsDirectVideo => false;

  @override
  Future<Lesson> generateLessonJson({
    required List<VideoFrame> frames,
    required SelectedVideo video,
    required String audience,
    required String goal,
    required LessonPrompt prompt,
  }) async {
    final now = DateTime.now();
    final annotatedFrames = frames
        .where((frame) => frame.touchTarget != null)
        .toList();
    if (annotatedFrames.isNotEmpty) {
      return _generateFromAnnotations(
        frames: frames,
        annotatedFrames: annotatedFrames,
        video: video,
        goal: goal,
        now: now,
      );
    }

    final stepCount = frames.length.clamp(3, 5);
    final templates = <_StepTemplate>[
      const _StepTemplate(
        title: '找到要操作的位置',
        instruction: '先看清屏幕上的主要按钮或输入框，确认要点击的位置。',
        type: LessonActionType.observe,
        target: RelativeTarget(
          x: 0.5,
          y: 0.35,
          width: 0.5,
          height: 0.16,
          label: '主要操作区域',
        ),
        elderTip: '不要着急，先把屏幕内容看清楚。',
      ),
      const _StepTemplate(
        title: '轻点目标按钮',
        instruction: '用手指轻轻点一下高亮位置，等待手机进入下一步。',
        type: LessonActionType.tap,
        target: RelativeTarget(
          x: 0.72,
          y: 0.78,
          width: 0.22,
          height: 0.1,
          label: '下一步按钮',
        ),
        elderTip: '点击后等一两秒，不需要连续点很多次。',
      ),
      const _StepTemplate(
        title: '检查页面变化',
        instruction: '确认页面已经切换，看看是否出现新的提示或确认按钮。',
        type: LessonActionType.wait,
        target: RelativeTarget(
          x: 0.5,
          y: 0.5,
          width: 0.72,
          height: 0.38,
          label: '页面内容',
        ),
        elderTip: '如果页面没反应，可以再轻点一次，不要用力按屏幕。',
      ),
      const _StepTemplate(
        title: '完成确认',
        instruction: '看到确认、完成或保存按钮后，轻点它来结束本次操作。',
        type: LessonActionType.tap,
        target: RelativeTarget(
          x: 0.5,
          y: 0.86,
          width: 0.42,
          height: 0.1,
          label: '确认按钮',
        ),
        elderTip: '按钮通常在屏幕底部或右上角。',
      ),
      const _StepTemplate(
        title: '回到安全页面',
        instruction: '操作结束后，确认结果已经保存，再返回上一页或关闭页面。',
        type: LessonActionType.observe,
        target: RelativeTarget(
          x: 0.18,
          y: 0.08,
          width: 0.18,
          height: 0.1,
          label: '返回位置',
        ),
        elderTip: '如果不确定是否完成，先不要退出，找家人确认也可以。',
      ),
    ];

    return Lesson(
      schemaVersion: lessonSchemaVersion,
      id: 'lesson_${now.millisecondsSinceEpoch}',
      title: '老人手机操作指导教程',
      summary: '根据 ${video.name} 生成的模拟教程：$goal',
      createdAt: now,
      source: LessonSource(
        type: 'video_frames',
        frameCount: frames.length,
        generator: 'mock',
      ),
      steps: [
        for (var index = 0; index < stepCount; index += 1)
          LessonStep(
            id: 'step_${index + 1}',
            order: index + 1,
            title: templates[index].title,
            instruction: templates[index].instruction,
            action: LessonAction(
              type: templates[index].type,
              target: templates[index].target,
            ),
            frameIndex: index.clamp(0, frames.length - 1),
            elderTip: templates[index].elderTip,
          ),
      ],
    );
  }

  Lesson _generateFromAnnotations({
    required List<VideoFrame> frames,
    required List<VideoFrame> annotatedFrames,
    required SelectedVideo video,
    required String goal,
    required DateTime now,
  }) {
    return Lesson(
      schemaVersion: lessonSchemaVersion,
      id: 'lesson_${now.millisecondsSinceEpoch}',
      title: '老人手机操作指导教程',
      summary: '根据 ${video.name} 的真实标注位置生成模拟教程：$goal',
      createdAt: now,
      source: LessonSource(
        type: 'video_frames',
        frameCount: frames.length,
        generator: 'mock',
      ),
      steps: [
        for (final indexed in annotatedFrames.indexed)
          LessonStep(
            id: 'step_${indexed.$1 + 1}',
            order: indexed.$1 + 1,
            title: '轻点第 ${indexed.$1 + 1} 个标注位置',
            instruction: '看准画面中的高亮框，用手指轻轻点一下这个位置。',
            action: LessonAction(
              type: LessonActionType.tap,
              target: indexed.$2.touchTarget!,
            ),
            frameIndex: indexed.$2.index,
            elderTip: '点击后先等一两秒，看到页面变化后再继续下一步。',
          ),
      ],
    );
  }

  @override
  Future<UIPage?> generateUI({
    required List<VideoFrame> frames,
    required List<({double x, double y})> markedPositions,
    required String goal,
  }) async {
    return UIPage(
      title: '操作练习',
      backgroundColor: '#F2F2F7',
      appBar: const UIAppBar(
        title: '操作练习',
        showBackButton: false,
      ),
      body: UIWidget(
        type: 'column',
        children: [
          const UIWidget(
            type: 'text',
            content: '请依次点击下面的按钮，完成操作',
            fontSize: 16,
            fontWeight: 'bold',
            color: '#333333',
          ),
          const UIWidget(type: 'divider'),
          ...markedPositions.asMap().entries.map((e) => UIWidget(
                type: 'button',
                label: '步骤 ${e.key + 1}',
                backgroundColor: '#007AFF',
                textColor: '#FFFFFF',
                borderRadius: 12,
                fontSize: 17,
                fontWeight: 'bold',
                isTarget: true,
                stepIndex: e.key + 1,
                instruction: '请点击「步骤 ${e.key + 1}」按钮',
              )),
        ],
      ),
    );
  }

  @override
  Future<ButtonAnalysis?> analyzeButton({
    required VideoFrame frame,
    required double markedX,
    required double markedY,
    required String goal,
  }) async {
    return ButtonAnalysis(
      boundingBox: BoundingBox(
        x: (markedX * 1000).roundToDouble() / 1000,
        y: (markedY * 1000).roundToDouble() / 1000,
        width: 0.16,
        height: 0.07,
      ),
      label: '按钮',
      actionDescription: '点击进入下一步操作',
      instruction: '请点击屏幕中标注位置的按钮',
      elderTip: '如果不确定，可以先观察按钮上的文字再点击',
      buttonStyle: const ButtonStyleInfo(
        backgroundColor: '#007AFF',
        textColor: '#FFFFFF',
        borderRadius: 12,
        fontSize: 17,
        fontWeight: 'bold',
      ),
    );
  }
}

class _StepTemplate {
  const _StepTemplate({
    required this.title,
    required this.instruction,
    required this.type,
    required this.target,
    required this.elderTip,
  });

  final String title;
  final String instruction;
  final LessonActionType type;
  final RelativeTarget target;
  final String elderTip;
}
