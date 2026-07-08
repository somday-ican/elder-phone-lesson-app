import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'generation/lesson_validator.dart';
import 'generation/mock_lesson_generator.dart';
import 'generation/model_client.dart';
import 'generation/prompt_builder.dart';
import 'generation/remote_multimodal_model_client.dart';
import 'models/button_analysis.dart';
import 'models/lesson.dart';
import 'models/video_frame.dart';
import 'processing/image_processor.dart';
import 'screens/ui_practice_page.dart';
import 'vision/touch_indicator_detector.dart';
import 'widgets/frame_stage.dart';

class VideoToLessonApp extends StatelessWidget {
  const VideoToLessonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '长辈学手机',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AFF),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: ScreenshotLessonPage(modelClient: _buildModelClient()),
    );
  }

  ModelClient _buildModelClient() {
    const endpoint = String.fromEnvironment('LESSON_API_URL');
    if (endpoint.isEmpty) {
      return const MockLessonGenerator();
    }
    return RemoteMultimodalModelClient(endpoint: Uri.parse(endpoint));
  }
}

class ScreenshotLessonPage extends StatefulWidget {
  const ScreenshotLessonPage({
    super.key,
    this.imagePicker,
    this.promptBuilder = const PromptBuilder(),
    this.modelClient = const MockLessonGenerator(),
    this.lessonValidator = const LessonValidator(),
    this.redCircleDetector = const RedCircleDetector(),
    this.imageProcessor = const ImageProcessor(),
  });

  final ImagePicker? imagePicker;
  final PromptBuilder promptBuilder;
  final ModelClient modelClient;
  final LessonValidator lessonValidator;
  final RedCircleDetector redCircleDetector;
  final ImageProcessor imageProcessor;

  @override
  State<ScreenshotLessonPage> createState() => _ScreenshotLessonPageState();
}

class _ScreenshotLessonPageState extends State<ScreenshotLessonPage> {
  final _goalController = TextEditingController(
    text: '把截图里的手机操作讲成适合老人照做的步骤',
  );
  List<VideoFrame> _images = [];
  Map<int, ButtonAnalysis> _buttonAnalyses = {};
  Map<int, ProcessedButton> _processedButtons = {};
  Lesson? _lesson;
  int _selectedImageIndex = 0;
  int _activeStepIndex = 0;
  Timer? _playTimer;
  Timer? _practiceTimer;
  bool _isPicking = false;
  bool _isGenerating = false;
  bool _isAnalyzing = false;
  bool _isDetecting = false;
  String _status = '请选择一组截图，然后逐张点击标记操作位置';

  // Marking mode
  bool _isMarking = false;
  int _markingIndex = 0;

  // Practice mode
  bool _isPracticeMode = false;
  int _practiceIndex = 0;
  int _practiceCorrectCount = 0;
  int _practiceWrongCount = 0;

  // Path selection
  bool _showPathPicker = false;

  ImagePicker get _picker => widget.imagePicker ?? ImagePicker();

  @override
  void dispose() {
    _goalController.dispose();
    _playTimer?.cancel();
    _practiceTimer?.cancel();
    super.dispose();
  }

  // ── Pick images ─────────────────────────────────────────────────

  Future<void> _pickImages() async {
    setState(() {
      _isPicking = true;
      _status = '正在打开图片选择器';
    });

    try {
      final files = await _picker.pickMultiImage(
        imageQuality: 86,
        requestFullMetadata: false,
      );
      if (files.isEmpty) {
        setState(() => _status = '未选择截图');
        return;
      }

      final frames = <VideoFrame>[];
      for (final indexed in files.indexed) {
        final bytes = await File(indexed.$2.path).readAsBytes();
        frames.add(VideoFrame(
          index: indexed.$1,
          time: Duration(milliseconds: indexed.$1),
          bytes: bytes,
        ));
      }

      setState(() {
        _images = frames;
        _lesson = null;
        _buttonAnalyses = {};
        _processedButtons = {};
        _selectedImageIndex = 0;
        _activeStepIndex = 0;
        _isMarking = false;
        _markingIndex = 0;
        _showPathPicker = false;
        _status = '已选择 ${frames.length} 张截图，请点击「标注位置」逐张标记';
      });
    } catch (error) {
      setState(() => _status = '图片读取失败：$error');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  // ── Marking mode ────────────────────────────────────────────────

  int get _markedCount =>
      _images.where((f) => f.touchTarget != null).length;

  void _startMarking() {
    if (_images.isEmpty) return;
    setState(() {
      _isMarking = true;
      _markingIndex = 0;
      _status = '点击图片中需要操作的位置（第 1/${_images.length} 张）';
    });
  }

  void _handleMarkTap(int imageIndex, Offset relativePosition) {
    if (!_isMarking) return;
    final frame = _images[imageIndex];
    final updated = frame.copyWith(
      touchTarget: RelativeTarget(
        x: relativePosition.dx,
        y: relativePosition.dy,
        width: 0.24,
        height: 0.16,
        label: '第 ${imageIndex + 1} 步',
      ),
    );
    setState(() {
      _images = [
        for (final f in _images)
          if (f.index == imageIndex) updated else f,
      ];
      _buttonAnalyses.remove(imageIndex);
      _processedButtons.remove(imageIndex);
      _status = '已标记第 ${imageIndex + 1} 张 ✓';
    });
  }

  void _nextMarkingImage() {
    if (_markingIndex >= _images.length - 1) {
      _finishMarking();
      return;
    }
    setState(() {
      _markingIndex++;
      _status = '点击图片中需要操作的位置（第 ${_markingIndex + 1}/${_images.length} 张）';
    });
  }

  void _prevMarkingImage() {
    if (_markingIndex <= 0) return;
    setState(() {
      _markingIndex--;
      _status = '点击图片中需要操作的位置（第 ${_markingIndex + 1}/${_images.length} 张）';
    });
  }

  void _jumpToMarkingImage(int index) {
    setState(() {
      _markingIndex = index.clamp(0, _images.length - 1);
      _status = '点击图片中需要操作的位置（第 ${_markingIndex + 1}/${_images.length} 张）';
    });
  }

  void _clearCurrentMark() {
    final frame = _images[_markingIndex];
    setState(() {
      _images = [
        for (final f in _images)
          if (f.index == frame.index)
            frame.copyWith(clearTouchTarget: true)
          else
            f,
      ];
      _buttonAnalyses.remove(_markingIndex);
      _processedButtons.remove(_markingIndex);
      _status = '已清除第 ${_markingIndex + 1} 张标记';
    });
  }

  void _finishMarking() {
    setState(() {
      _isMarking = false;
      _showPathPicker = true;
      _status = '标注完成（$_markedCount/${_images.length} 张），请选择下一步';
    });
  }

  void _exitMarking() {
    setState(() {
      _isMarking = false;
      _showPathPicker = false;
      _status = '已退出标注，已标记 $_markedCount 张';
    });
  }

  // ── AI Button Analysis ──────────────────────────────────────────

  Future<void> _analyzeButtons() async {
    final unanalyzed = _images
        .where((f) =>
            f.touchTarget != null &&
            !_buttonAnalyses.containsKey(f.index))
        .toList();

    if (unanalyzed.isEmpty) {
      setState(() => _status = '所有已标记截图已完成分析');
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _status = 'AI 正在分析按钮位置和样式...';
    });

    try {
      for (final frame in unanalyzed) {
        setState(() => _status = 'AI 分析中（${frame.index + 1}/${_images.length}）...');

        final target = frame.touchTarget!;
        final analysis = await widget.modelClient.analyzeButton(
          frame: frame,
          markedX: target.x,
          markedY: target.y,
          goal: _goalController.text.trim(),
        );

        if (analysis != null && mounted) {
          // Update the frame's target with AI-refined bounding box
          final updated = frame.copyWith(
            touchTarget: analysis.boundingBox.toRelativeTarget(
              label: analysis.label,
            ),
          );
          setState(() {
            _images = [
              for (final f in _images)
                if (f.index == frame.index) updated else f,
            ];
            _buttonAnalyses[frame.index] = analysis;
          });

          // Generate blurred button image
          try {
            final processed = await widget.imageProcessor.extractBlurredButton(
              sourceBytes: frame.bytes,
              boundingBox: analysis.boundingBox,
              scale: 1.5,
              blurRadius: 14,
            );
            if (mounted) {
              setState(() => _processedButtons[frame.index] = processed);
            }
          } catch (_) {
            // Image processing failed — fall back to simple overlay
          }
        }
      }

      setState(() {
        _isAnalyzing = false;
        _showPathPicker = true;
        final analyzed = _buttonAnalyses.length;
        _status = analyzed > 0
            ? 'AI 分析完成（$analyzed 张），已生成放大虚化按钮'
            : 'AI 分析完成';
      });
    } catch (error) {
      setState(() {
        _isAnalyzing = false;
        _status = 'AI 分析失败：$error，将使用标记位置练习';
      });
    }
  }

  // ── Auto-detect red circles ─────────────────────────────────────

  Future<void> _detectRedCircles() async {
    if (_images.isEmpty) return;
    setState(() {
      _isDetecting = true;
      _status = '正在识别红圈标注...';
    });

    try {
      final detections = await widget.redCircleDetector.detect(_images);
      final detectionsByFrame = {
        for (final d in detections) d.frameIndex: d,
      };

      var added = 0;
      setState(() {
        _images = [
          for (final frame in _images)
            if (detectionsByFrame.containsKey(frame.index) &&
                frame.touchTarget == null)
              frame.copyWith(
                touchTarget: detectionsByFrame[frame.index]!.target,
              )
            else
              frame,
        ];
        added = detections.length;
      });

      setState(() {
        _isDetecting = false;
        _status = added > 0
            ? '自动识别到 $added 个红圈'
            : '未识别到红圈，请手动标注';
      });
    } catch (error) {
      setState(() {
        _isDetecting = false;
        _status = '红圈识别失败：$error';
      });
    }
  }

  // ── AI Generate lesson ──────────────────────────────────────────

  Future<void> _generateLesson() async {
    if (_images.isEmpty) return;
    setState(() {
      _isGenerating = true;
      _status = 'AI 正在生成教程...';
    });

    try {
      final goal = _goalController.text.trim();
      final source = SelectedVideo(
        path: 'screenshots',
        name: 'screenshots',
        mimeType: 'image/jpeg',
        duration: Duration(milliseconds: _images.length),
        aspectRatio: 9 / 16,
      );
      final prompt = widget.promptBuilder.build(
        frames: _images,
        video: source,
        audience: 'elderly smartphone user',
        goal: goal,
      );
      final lesson = await widget.modelClient.generateLessonJson(
        frames: _images,
        video: source,
        audience: 'elderly smartphone user',
        goal: goal,
        prompt: prompt,
      );
      final validation = widget.lessonValidator.validate(lesson);
      if (!validation.ok) throw StateError(validation.errors.join('\n'));

      setState(() {
        _lesson = lesson;
        _activeStepIndex = 0;
        _showPathPicker = false;
        _status = '教程已生成 ✓';
      });
    } catch (error) {
      setState(() => _status = '生成失败：$error');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  // ── UI Generation (Path 2) ──────────────────────────────────────

  Future<void> _generateUIAndStartPractice() async {
    final framesWithTargets = _framesWithTargets;
    if (framesWithTargets.isEmpty) {
      setState(() => _status = '请先标注操作位置');
      return;
    }

    setState(() {
      _isGenerating = true;
      _status = 'AI 正在生成仿真界面...';
    });

    try {
      final positions = framesWithTargets
          .map((f) => (x: f.touchTarget!.x, y: f.touchTarget!.y))
          .toList();

      final uiPage = await widget.modelClient.generateUI(
        frames: _images,
        markedPositions: positions,
        goal: _goalController.text.trim(),
      );

      if (uiPage != null && mounted) {
        setState(() {
          _isGenerating = false;
          _showPathPicker = false;
        });

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UIPracticePage(
              page: uiPage,
              targetCount: framesWithTargets.length,
            ),
          ),
        );
      } else {
        setState(() {
          _isGenerating = false;
          _status = 'UI 生成失败，请使用图片模式';
        });
      }
    } catch (error) {
      setState(() {
        _isGenerating = false;
        _status = 'UI 生成失败：$error，请使用图片模式';
      });
    }
  }

  // ── Practice mode ───────────────────────────────────────────────

  List<VideoFrame> get _framesWithTargets =>
      _images.where((f) => f.touchTarget != null).toList();

  void _startPractice() {
    final targets = _framesWithTargets;
    if (targets.isEmpty) {
      setState(() => _status = '请先标注操作位置再练习');
      return;
    }

    setState(() {
      _isPracticeMode = true;
      _showPathPicker = false;
      _practiceIndex = 0;
      _practiceCorrectCount = 0;
      _practiceWrongCount = 0;
      _status = '练习模式（${targets.length} 步）';
    });
  }

  void _handlePracticeTap(int imageIndex, bool correct) {
    if (!_isPracticeMode) return;
    if (correct) {
      setState(() => _practiceCorrectCount++);
      _practiceTimer?.cancel();
      _practiceTimer = Timer(const Duration(milliseconds: 1000), () {
        if (!mounted || !_isPracticeMode) return;
        final targets = _framesWithTargets;
        if (_practiceIndex >= targets.length - 1) {
          _finishPractice();
        } else {
          setState(() => _practiceIndex++);
        }
      });
    } else {
      setState(() => _practiceWrongCount++);
    }
  }

  void _finishPractice() {
    _practiceTimer?.cancel();
    setState(() {
      _isPracticeMode = false;
      _practiceIndex = 0;
      _status = '练习完成！✓$_practiceCorrectCount  ✗$_practiceWrongCount';
    });
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 32),
            SizedBox(width: 10),
            Text('练习完成', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ScoreRow(label: '正确', value: _practiceCorrectCount, color: Colors.green),
            const SizedBox(height: 6),
            _ScoreRow(label: '错误', value: _practiceWrongCount, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _practiceWrongCount == 0
                  ? '太棒了！全部点对了！🎉'
                  : '继续加油，多练几次就熟了 💪',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }

  void _exitPractice() {
    _practiceTimer?.cancel();
    setState(() {
      _isPracticeMode = false;
      _practiceIndex = 0;
      _status = '已退出练习';
    });
  }

  // ── Lesson navigation ──────────────────────────────────────────

  void _showStep(int index) {
    if (_lesson == null) return;
    setState(() => _activeStepIndex = index.clamp(0, _lesson!.steps.length - 1));
  }

  void _selectImage(int index) {
    setState(() => _selectedImageIndex = index.clamp(0, _images.length - 1));
  }

  void _toggleLessonPlayback() {
    if (_playTimer != null) { _stopPlayback(); return; }
    final lesson = _lesson;
    if (lesson == null || lesson.steps.isEmpty) return;
    _playTimer = Timer.periodic(const Duration(seconds: 3), (t) {
      if (_activeStepIndex >= lesson.steps.length - 1) {
        _stopPlayback();
      } else {
        _showStep(_activeStepIndex + 1);
      }
    });
    setState(() {});
  }

  void _stopPlayback() {
    _playTimer?.cancel();
    _playTimer = null;
    if (mounted) setState(() {});
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isMarking) return _buildMarkingScaffold();
    if (_isPracticeMode) return _buildPracticeScaffold();

    final lesson = _lesson;
    final activeStep = lesson == null ? null : lesson.steps[_activeStepIndex];
    final activeFrame = activeStep == null || _images.isEmpty
        ? null
        : _images[activeStep.frameIndex.clamp(0, _images.length - 1)];
    final selectedImage = _images.isEmpty
        ? null
        : _images[_selectedImageIndex.clamp(0, _images.length - 1)];

    return Scaffold(
      appBar: AppBar(
        title: const Text('长辈学手机', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_images.length} 张',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _StatusPanel(status: _status),
            const SizedBox(height: 16),
            _buildGoalField(),
            const SizedBox(height: 16),
            _ActionBar(
              isBusy: _isPicking || _isGenerating || _isAnalyzing || _isDetecting,
              hasImages: _images.isNotEmpty,
              markedCount: _markedCount,
              totalCount: _images.length,
              analyzedCount: _buttonAnalyses.length,
              onPickImages: _pickImages,
              onStartMarking: _startMarking,
              onAnalyzeButtons: _analyzeButtons,
              onDetectRedCircles: _detectRedCircles,
              onGenerateLesson: _generateLesson,
              onStartPractice: _startPractice,
            ),
            if (_showPathPicker) ...[
              const SizedBox(height: 20),
              _PathPicker(
                onPracticeSimple: _startPractice,
                onPracticeReconstructed: _generateUIAndStartPractice,
              ),
            ],
            if (selectedImage != null) ...[
              const SizedBox(height: 20),
              _ImagePreviewPanel(
                images: _images,
                selectedImage: selectedImage,
                selectedIndex: _selectedImageIndex,
                buttonAnalyses: _buttonAnalyses,
                onSelectImage: _selectImage,
              ),
            ],
            const SizedBox(height: 20),
            if (lesson == null)
              const _EmptyLessonPanel()
            else
              _LessonPanel(
                lesson: lesson,
                activeStepIndex: _activeStepIndex,
                activeFrame: activeFrame,
                processedButton: activeFrame != null
                    ? _processedButtons[activeFrame.index]
                    : null,
                isPlaying: _playTimer != null,
                onPrevious: () => _showStep(_activeStepIndex - 1),
                onNext: () => _showStep(_activeStepIndex + 1),
                onTogglePlayback: _toggleLessonPlayback,
                onSelectStep: _showStep,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _goalController,
        minLines: 2,
        maxLines: 3,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          labelText: '学习目标',
          labelStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  // ── Marking scaffold ───────────────────────────────────────────

  Scaffold _buildMarkingScaffold() {
    final frame = _images[_markingIndex];
    final hasTarget = frame.touchTarget != null;
    final analysis = _buttonAnalyses[frame.index];

    return Scaffold(
      appBar: AppBar(
        title: Text('标注位置 ${_markingIndex + 1}/${_images.length}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _exitMarking,
        ),
        actions: [
          if (hasTarget)
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: '清除',
              onPressed: _clearCurrentMark,
            ),
          IconButton(
            icon: const Icon(Icons.check_rounded),
            tooltip: '完成',
            onPressed: _finishMarking,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: hasTarget
                          ? Colors.green.withValues(alpha: 0.12)
                          : Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      hasTarget ? Icons.check_circle_rounded : Icons.touch_app_rounded,
                      color: hasTarget ? Colors.green : Colors.orange,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hasTarget
                          ? '已标记 ✓ 点击其他位置可重标'
                          : '点击截图中需要操作的按钮位置',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (analysis != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('AI 已分析', style: TextStyle(fontSize: 12, color: Colors.blue)),
                    ),
                ],
              ),
            ),
            // Step indicators
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  for (var i = 0; i < _images.length; i++)
                    Expanded(
                      child: Container(
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: i == _markingIndex
                              ? Theme.of(context).colorScheme.primary
                              : i < _markingIndex
                                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)
                                  : Colors.grey.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: FrameStage(
                  key: ValueKey('mark_${frame.index}'),
                  frame: frame,
                  aspectRatio: 9 / 16,
                  target: frame.touchTarget,
                  onTapRelative: (pos) => _handleMarkTap(frame.index, pos),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildMarkingBottomBar(),
    );
  }

  Widget _buildMarkingBottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton.filledTonal(
              onPressed: _markingIndex > 0 ? _prevMarkingImage : null,
              icon: const Icon(Icons.chevron_left_rounded),
              style: IconButton.styleFrom(
                backgroundColor: Colors.grey.withValues(alpha: 0.1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _images.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final f = _images[index];
                    final isCurrent = index == _markingIndex;
                    final isMarked = f.touchTarget != null;
                    return GestureDetector(
                      onTap: () => _jumpToMarkingImage(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isCurrent
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 2.5,
                          ),
                          boxShadow: isCurrent
                              ? [
                                  BoxShadow(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.3),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(f.bytes, fit: BoxFit.cover),
                              if (isMarked)
                                Positioned(
                                  top: 3,
                                  right: 3,
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: const BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 10,
                                    ),
                                  ),
                                ),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  color: Colors.black.withValues(alpha: 0.45),
                                  child: Text(
                                    '${index + 1}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _markingIndex < _images.length - 1
                  ? _nextMarkingImage
                  : _finishMarking,
              icon: Icon(
                _markingIndex < _images.length - 1
                    ? Icons.chevron_right_rounded
                    : Icons.check_rounded,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Practice scaffold ──────────────────────────────────────────

  Scaffold _buildPracticeScaffold() {
    final targets = _framesWithTargets;
    if (targets.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('练习模式')),
        body: const Center(child: Text('没有可练习的步骤')),
      );
    }

    final frame = targets[_practiceIndex];
    final target = frame.touchTarget;
    final processed = _processedButtons[frame.index];
    final analysis = _buttonAnalyses[frame.index];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        title: Text(
          '练习 ${_practiceIndex + 1}/${targets.length}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: _exitPractice,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ScoreChip(icon: Icons.check, value: _practiceCorrectCount, color: Colors.green),
                const SizedBox(width: 8),
                _ScoreChip(icon: Icons.close, value: _practiceWrongCount, color: Colors.red),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  for (var i = 0; i < targets.length; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: i < _practiceIndex
                              ? Colors.green
                              : i == _practiceIndex
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Instruction
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                analysis?.instruction ??
                    '请点击图中标注的按钮位置（第 ${_practiceIndex + 1} 步）',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // Image with interactive target
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: FrameStage(
                  key: ValueKey('practice_${frame.index}_$_practiceIndex'),
                  frame: frame,
                  aspectRatio: 9 / 16,
                  target: target,
                  processedButton: processed,
                  interactive: true,
                  hitRadius: 0.20,
                  onPracticeResult: (correct) {
                    _handlePracticeTap(frame.index, correct);
                  },
                ),
              ),
            ),
            // Tip
            if (analysis != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline, color: Colors.amber, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          analysis.elderTip,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              status,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.isBusy,
    required this.hasImages,
    required this.markedCount,
    required this.totalCount,
    required this.analyzedCount,
    required this.onPickImages,
    required this.onStartMarking,
    required this.onAnalyzeButtons,
    required this.onDetectRedCircles,
    required this.onGenerateLesson,
    required this.onStartPractice,
  });

  final bool isBusy;
  final bool hasImages;
  final int markedCount;
  final int totalCount;
  final int analyzedCount;
  final VoidCallback onPickImages;
  final VoidCallback onStartMarking;
  final VoidCallback onAnalyzeButtons;
  final VoidCallback onDetectRedCircles;
  final VoidCallback onGenerateLesson;
  final VoidCallback onStartPractice;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 10, runSpacing: 10, children: [
      _ActionButton(
        icon: Icons.photo_library_outlined,
        label: '选择截图',
        onTap: isBusy ? null : onPickImages,
        variant: _BtnVariant.primary,
      ),
      _ActionButton(
        icon: Icons.edit_location_alt_outlined,
        label: '标注 ($markedCount/$totalCount)',
        onTap: isBusy || !hasImages ? null : onStartMarking,
        variant: _BtnVariant.tonal,
      ),
      _ActionButton(
        icon: Icons.auto_awesome_outlined,
        label: analyzedCount > 0 ? 'AI 分析 ($analyzedCount)' : 'AI 分析按钮',
        onTap: isBusy || markedCount == 0 ? null : onAnalyzeButtons,
        variant: _BtnVariant.tonal,
      ),
      const _Divider(),
      _ActionButton(
        icon: Icons.school_outlined,
        label: '生成教程',
        onTap: isBusy || !hasImages ? null : onGenerateLesson,
        variant: _BtnVariant.tonal,
      ),
      _ActionButton(
        icon: Icons.play_circle,
        label: '开始练习 ($markedCount)',
        onTap: isBusy || markedCount == 0 ? null : onStartPractice,
        variant: _BtnVariant.accent,
      ),
    ]);
  }
}

enum _BtnVariant { primary, tonal, accent }

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.variant,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final _BtnVariant variant;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;

    Widget child;
    switch (variant) {
      case _BtnVariant.primary:
        child = FilledButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      case _BtnVariant.tonal:
        child = FilledButton.tonalIcon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
        );
      case _BtnVariant.accent:
        child = FilledButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: enabled ? Colors.green.shade600 : Colors.grey,
            foregroundColor: Colors.white,
          ),
        );
    }
    return child;
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => const SizedBox(width: 2);
}

class _PathPicker extends StatelessWidget {
  const _PathPicker({
    required this.onPracticeSimple,
    required this.onPracticeReconstructed,
  });

  final VoidCallback onPracticeSimple;
  final VoidCallback onPracticeReconstructed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择练习方式',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _PathCard(
              icon: Icons.image_outlined,
              title: '图片模式',
              subtitle: '在截图上练习\n按钮放大+虚化效果',
              isRecommended: true,
              onTap: onPracticeSimple,
            )),
            const SizedBox(width: 12),
            Expanded(child: _PathCard(
              icon: Icons.widgets_outlined,
              title: '仿真模式',
              subtitle: 'AI 重建真实界面\n更沉浸的练习体验',
              onTap: onPracticeReconstructed,
            )),
          ],
        ),
      ],
    );
  }
}

class _PathCard extends StatelessWidget {
  const _PathCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isRecommended = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isRecommended;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRecommended
                ? theme.colorScheme.primary.withValues(alpha: 0.4)
                : Colors.grey.withValues(alpha: 0.15),
            width: isRecommended ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isRecommended
                        ? theme.colorScheme.primary.withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isRecommended
                        ? theme.colorScheme.primary
                        : Colors.grey,
                    size: 22,
                  ),
                ),
                const Spacer(),
                if (isRecommended)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '推荐',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.3)),
          ],
        ),
      ),
    );
  }
}

class _ImagePreviewPanel extends StatelessWidget {
  const _ImagePreviewPanel({
    required this.images,
    required this.selectedImage,
    required this.selectedIndex,
    required this.buttonAnalyses,
    required this.onSelectImage,
  });

  final List<VideoFrame> images;
  final VideoFrame selectedImage;
  final int selectedIndex;
  final Map<int, ButtonAnalysis> buttonAnalyses;
  final ValueChanged<int> onSelectImage;

  @override
  Widget build(BuildContext context) {
    final analysis = buttonAnalyses[selectedImage.index];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('截图预览', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            if (selectedImage.touchTarget != null)
              Chip(
                avatar: Icon(
                  analysis != null ? Icons.auto_awesome : Icons.touch_app,
                  color: analysis != null ? Colors.blue : Colors.orange,
                  size: 16,
                ),
                label: Text(
                  analysis?.label ?? '已标注',
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: analysis != null
                    ? Colors.blue.withValues(alpha: 0.08)
                    : Colors.orange.withValues(alpha: 0.08),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        FrameStage(
          frame: selectedImage,
          aspectRatio: 9 / 16,
          target: selectedImage.touchTarget,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final f = images[index];
              final selected = index == selectedIndex;
              final hasTarget = f.touchTarget != null;
              final hasAi = buttonAnalyses.containsKey(f.index);
              return GestureDetector(
                onTap: () => onSelectImage(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 72,
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(f.bytes, fit: BoxFit.cover),
                        if (hasTarget)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: hasAi ? Colors.blue : Colors.green,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                hasAi ? Icons.auto_awesome : Icons.check,
                                color: Colors.white,
                                size: 9,
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            color: Colors.black.withValues(alpha: 0.5),
                            child: Text(
                              '${index + 1}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyLessonPanel extends StatelessWidget {
  const _EmptyLessonPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: Text('教程会在这里展示', style: TextStyle(color: Colors.grey, fontSize: 15)),
      ),
    );
  }
}

class _LessonPanel extends StatelessWidget {
  const _LessonPanel({
    required this.lesson,
    required this.activeStepIndex,
    required this.activeFrame,
    required this.isPlaying,
    required this.onPrevious,
    required this.onNext,
    required this.onTogglePlayback,
    required this.onSelectStep,
    this.processedButton,
  });

  final Lesson lesson;
  final int activeStepIndex;
  final VideoFrame? activeFrame;
  final bool isPlaying;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onTogglePlayback;
  final ValueChanged<int> onSelectStep;
  final ProcessedButton? processedButton;

  @override
  Widget build(BuildContext context) {
    final step = lesson.steps[activeStepIndex];
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(lesson.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(lesson.summary, style: TextStyle(color: Colors.grey.shade600)),
        const SizedBox(height: 14),
        if (activeFrame != null)
          FrameStage(
            frame: activeFrame!,
            aspectRatio: 9 / 16,
            target: step.action.target,
            processedButton: processedButton,
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${activeStepIndex + 1} / ${lesson.steps.length}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(step.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(step.instruction, style: theme.textTheme.bodyLarge),
        if (step.elderTip != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline, size: 18, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(child: Text(step.elderTip!, style: const TextStyle(fontSize: 14))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            _NavButton(
              icon: Icons.chevron_left_rounded,
              enabled: activeStepIndex > 0,
              onTap: onPrevious,
            ),
            const SizedBox(width: 8),
            _NavButton(
              icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              enabled: true,
              onTap: onTogglePlayback,
              isPrimary: true,
            ),
            const SizedBox(width: 8),
            _NavButton(
              icon: Icons.chevron_right_rounded,
              enabled: activeStepIndex < lesson.steps.length - 1,
              onTap: onNext,
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...lesson.steps.indexed.map((indexed) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: indexed.$1 == activeStepIndex
                    ? theme.colorScheme.primary
                    : Colors.grey.withValues(alpha: 0.15),
                child: Text(
                  '${indexed.$2.order}',
                  style: TextStyle(
                    color: indexed.$1 == activeStepIndex
                        ? Colors.white
                        : Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              title: Text(indexed.$2.title, style: const TextStyle(fontSize: 14)),
              subtitle: Text(indexed.$2.action.type.wireName, style: const TextStyle(fontSize: 12)),
              selected: indexed.$1 == activeStepIndex,
              onTap: () => onSelectStep(indexed.$1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            )),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.isPrimary = false,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 26),
      style: IconButton.styleFrom(
        backgroundColor: isPrimary
            ? enabled ? theme.colorScheme.primary : Colors.grey
            : Colors.grey.withValues(alpha: 0.1),
        foregroundColor: isPrimary ? Colors.white : theme.colorScheme.onSurface,
        padding: const EdgeInsets.all(10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final int value;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 4),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 16)),
        const Spacer(),
        Text('$value 次', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}
