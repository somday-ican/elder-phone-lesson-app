import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'generation/lesson_validator.dart';
import 'generation/mock_lesson_generator.dart';
import 'generation/model_client.dart';
import 'generation/prompt_builder.dart';
import 'generation/remote_multimodal_model_client.dart';
import 'models/lesson.dart';
import 'models/video_frame.dart';
import 'vision/touch_indicator_detector.dart';
import 'widgets/frame_stage.dart';

class VideoToLessonApp extends StatelessWidget {
  const VideoToLessonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '手机截图教程',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF25705A),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8F5),
        useMaterial3: true,
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
  });

  final ImagePicker? imagePicker;
  final PromptBuilder promptBuilder;
  final ModelClient modelClient;
  final LessonValidator lessonValidator;
  final RedCircleDetector redCircleDetector;

  @override
  State<ScreenshotLessonPage> createState() => _ScreenshotLessonPageState();
}

class _ScreenshotLessonPageState extends State<ScreenshotLessonPage> {
  final _goalController = TextEditingController(
    text: '把截图里的手机操作讲成适合老人照做的步骤',
  );
  List<VideoFrame> _images = [];
  Lesson? _lesson;
  int _selectedImageIndex = 0;
  int _activeStepIndex = 0;
  Timer? _playTimer;
  Timer? _practiceTimer;
  bool _isPicking = false;
  bool _isGenerating = false;
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
        setState(() {
          _status = '未选择截图';
        });
        return;
      }

      final frames = <VideoFrame>[];
      for (final indexed in files.indexed) {
        final bytes = await File(indexed.$2.path).readAsBytes();
        frames.add(
          VideoFrame(
            index: indexed.$1,
            time: Duration(milliseconds: indexed.$1),
            bytes: bytes,
          ),
        );
      }

      setState(() {
        _images = frames;
        _lesson = null;
        _selectedImageIndex = 0;
        _activeStepIndex = 0;
        _isMarking = false;
        _markingIndex = 0;
        _status = '已选择 ${frames.length} 张截图，请点击「标注位置」逐张标记操作按钮';
      });
    } catch (error) {
      setState(() {
        _status = '图片读取失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  // ── Manual marking mode ─────────────────────────────────────────

  int get _markedCount =>
      _images.where((f) => f.touchTarget != null).length;

  void _startMarking() {
    if (_images.isEmpty) {
      return;
    }
    setState(() {
      _isMarking = true;
      _markingIndex = 0;
      _status = '点击图片中需要操作的位置来标记（第 1/${_images.length} 张）';
    });
  }

  void _handleMarkTap(int imageIndex, Offset relativePosition) {
    if (!_isMarking) {
      return;
    }

    final frame = _images[imageIndex];
    final updated = frame.copyWith(
      touchTarget: RelativeTarget(
        x: relativePosition.dx,
        y: relativePosition.dy,
        width: 0.16,
        height: 0.10,
        label: '第 ${imageIndex + 1} 步操作位置',
      ),
    );

    setState(() {
      _images = [
        for (final f in _images)
          if (f.index == imageIndex) updated else f,
      ];
      _status = '已标记第 ${imageIndex + 1} 张，点击继续标记或切换图片';
    });
  }

  void _nextMarkingImage() {
    if (_markingIndex >= _images.length - 1) {
      _finishMarking();
      return;
    }
    setState(() {
      _markingIndex++;
      _status = '点击图片中需要操作的位置来标记（第 ${_markingIndex + 1}/${_images.length} 张）';
    });
  }

  void _prevMarkingImage() {
    if (_markingIndex <= 0) {
      return;
    }
    setState(() {
      _markingIndex--;
      _status = '点击图片中需要操作的位置来标记（第 ${_markingIndex + 1}/${_images.length} 张）';
    });
  }

  void _jumpToMarkingImage(int index) {
    setState(() {
      _markingIndex = index.clamp(0, _images.length - 1);
      _status = '点击图片中需要操作的位置来标记（第 ${_markingIndex + 1}/${_images.length} 张）';
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
      _status = '已清除第 ${_markingIndex + 1} 张标记';
    });
  }

  void _finishMarking() {
    setState(() {
      _isMarking = false;
      _status = '标注完成！已标记 $_markedCount/${_images.length} 张，可以开始练习';
    });
  }

  void _exitMarking() {
    setState(() {
      _isMarking = false;
      _status = '已退出标注模式，已标记 $_markedCount 张';
    });
  }

  // ── Auto-detect red circles (secondary) ─────────────────────────

  Future<void> _detectRedCircles() async {
    if (_images.isEmpty) {
      return;
    }

    setState(() {
      _isDetecting = true;
      _status = '正在尝试自动识别红圈标注';
    });

    try {
      final detections = await widget.redCircleDetector.detect(_images);
      final detectionsByFrame = {
        for (final detection in detections) detection.frameIndex: detection,
      };

      int added = 0;
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

      if (added > 0) {
        setState(() {
          _status = '自动识别到 $added 个红圈（仅补充未标注的图片），建议检查位置是否准确';
        });
      } else {
        setState(() {
          _status = '未识别到红圈，请使用手动标注模式';
        });
      }
    } catch (error) {
      setState(() {
        _status = '红圈识别失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isDetecting = false;
        });
      }
    }
  }

  // ── AI generate lesson ──────────────────────────────────────────

  Future<void> _generateLesson() async {
    if (_images.isEmpty) {
      return;
    }

    setState(() {
      _isGenerating = true;
      _status = '正在让 AI 分析截图并生成教程';
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
      if (!validation.ok) {
        throw StateError(validation.errors.join('\n'));
      }

      setState(() {
        _lesson = lesson;
        _activeStepIndex = 0;
        _status = '教程已生成，可一步步播放';
      });
    } catch (error) {
      setState(() {
        _status = '生成失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  // ── Practice mode ───────────────────────────────────────────────

  List<VideoFrame> get _framesWithTargets =>
      _images.where((f) => f.touchTarget != null).toList();

  void _startPractice() {
    final targets = _framesWithTargets;
    if (targets.isEmpty) {
      setState(() {
        _status = '请先标注操作位置再开始练习';
      });
      return;
    }
    if (targets.length < _images.length) {
      final proceed = _images.length - targets.length;
      setState(() {
        _status = '注意：还有 $proceed 张未标注，将只练习已标注的 ${targets.length} 张';
      });
    }

    setState(() {
      _isPracticeMode = true;
      _practiceIndex = 0;
      _practiceCorrectCount = 0;
      _practiceWrongCount = 0;
      _status = '练习模式：请点击图中标注的位置';
    });
  }

  void _handlePracticeTap(int imageIndex, bool correct) {
    if (!_isPracticeMode) {
      return;
    }

    if (correct) {
      setState(() {
        _practiceCorrectCount++;
      });

      _practiceTimer?.cancel();
      _practiceTimer = Timer(const Duration(milliseconds: 900), () {
        if (!mounted || !_isPracticeMode) {
          return;
        }
        final targets = _framesWithTargets;
        if (_practiceIndex >= targets.length - 1) {
          _finishPractice();
        } else {
          setState(() {
            _practiceIndex++;
          });
        }
      });
    } else {
      setState(() {
        _practiceWrongCount++;
      });
    }
  }

  void _finishPractice() {
    _practiceTimer?.cancel();
    setState(() {
      _isPracticeMode = false;
      _practiceIndex = 0;
      _status = '练习完成！正确 $_practiceCorrectCount 次，错误 $_practiceWrongCount 次';
    });

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.emoji_events, color: Colors.amber, size: 28),
              SizedBox(width: 8),
              Text('练习完成'),
            ],
          ),
          content: Text(
            '正确点击：$_practiceCorrectCount 次\n'
            '错误点击：$_practiceWrongCount 次\n\n'
            '${_practiceWrongCount == 0 ? "太棒了！你全部点对了！" : "继续加油，多练习几次就会熟悉的！"}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('好的'),
            ),
          ],
        );
      },
    );
  }

  void _exitPractice() {
    _practiceTimer?.cancel();
    setState(() {
      _isPracticeMode = false;
      _practiceIndex = 0;
      _status = '已退出练习模式';
    });
  }

  // ── Lesson navigation ──────────────────────────────────────────

  void _showStep(int index) {
    final lesson = _lesson;
    if (lesson == null) {
      return;
    }
    setState(() {
      _activeStepIndex = index.clamp(0, lesson.steps.length - 1);
    });
  }

  void _selectImage(int index) {
    setState(() {
      _selectedImageIndex = index.clamp(0, _images.length - 1);
    });
  }

  void _toggleLessonPlayback() {
    if (_playTimer != null) {
      _stopPlayback();
      return;
    }
    final lesson = _lesson;
    if (lesson == null || lesson.steps.isEmpty) {
      return;
    }

    _playTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
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
    if (mounted) {
      setState(() {});
    }
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Marking mode
    if (_isMarking) {
      return Scaffold(
        appBar: AppBar(
          title: Text('标注位置 ${_markingIndex + 1}/${_images.length}'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _exitMarking,
          ),
          actions: [
            if (_images[_markingIndex].touchTarget != null)
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: '清除当前标注',
                onPressed: _clearCurrentMark,
              ),
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: '完成标注',
              onPressed: _finishMarking,
            ),
          ],
        ),
        body: _buildMarkingView(),
        bottomNavigationBar: _buildMarkingBottomBar(),
      );
    }

    // Practice mode
    if (_isPracticeMode) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            '练习 ${_practiceIndex + 1}/${_framesWithTargets.length}',
          ),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _exitPractice,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '✓$_practiceCorrectCount  ✗$_practiceWrongCount',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ),
          ],
        ),
        body: _buildPracticeView(),
      );
    }

    // Main page
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
        title: const Text('手机截图教程生成器'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: Text('${_images.length} 张')),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _StatusPanel(status: _status),
            const SizedBox(height: 12),
            TextField(
              controller: _goalController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '生成目标',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _ActionBar(
              isPicking: _isPicking,
              isGenerating: _isGenerating,
              isDetecting: _isDetecting,
              hasImages: _images.isNotEmpty,
              markedCount: _markedCount,
              totalCount: _images.length,
              onPickImages: _pickImages,
              onStartMarking: _startMarking,
              onDetectRedCircles: _detectRedCircles,
              onGenerateLesson: _generateLesson,
              onStartPractice: _startPractice,
            ),
            if (selectedImage != null) ...[
              const SizedBox(height: 16),
              _ImagePreviewPanel(
                images: _images,
                selectedImage: selectedImage,
                selectedIndex: _selectedImageIndex,
                onSelectImage: _selectImage,
              ),
            ],
            const SizedBox(height: 16),
            if (lesson == null)
              const _EmptyLessonPanel()
            else
              _LessonPanel(
                lesson: lesson,
                activeStepIndex: _activeStepIndex,
                activeFrame: activeFrame,
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

  // ── Marking view ────────────────────────────────────────────────

  Widget _buildMarkingView() {
    final frame = _images[_markingIndex];
    final hasTarget = frame.touchTarget != null;

    return SafeArea(
      child: Column(
        children: [
          // Instruction
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(
                  hasTarget ? Icons.check_circle : Icons.touch_app,
                  color: hasTarget ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasTarget
                        ? '已标记 ✓ 点击其他位置可重新标记，或切换下一张'
                        : '请点击截图中需要操作的按钮/位置',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
          // Image with tap-to-mark
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FrameStage(
                key: ValueKey('mark_${frame.index}'),
                frame: frame,
                aspectRatio: 9 / 16,
                target: frame.touchTarget,
                onTapRelative: (pos) => _handleMarkTap(frame.index, pos),
              ),
            ),
          ),
          // Hint
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '点击图片中需要操作的位置，黄色框会显示标记区域',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkingBottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            IconButton.filledTonal(
              onPressed: _markingIndex > 0 ? _prevMarkingImage : null,
              icon: const Icon(Icons.chevron_left),
              tooltip: '上一张',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _images.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 4),
                  itemBuilder: (context, index) {
                    final frame = _images[index];
                    final isCurrent = index == _markingIndex;
                    final isMarked = frame.touchTarget != null;
                    return GestureDetector(
                      onTap: () => _jumpToMarkingImage(index),
                      child: Container(
                        width: 44,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isCurrent
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(
                                frame.bytes,
                                fit: BoxFit.cover,
                              ),
                              if (isMarked)
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: Container(
                                    width: 14,
                                    height: 14,
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
                              Container(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 1,
                                  ),
                                  color: Colors.black.withValues(alpha: 0.5),
                                  child: Text(
                                    '${index + 1}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
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
            IconButton.filledTonal(
              onPressed: _markingIndex < _images.length - 1
                  ? _nextMarkingImage
                  : _finishMarking,
              icon: Icon(
                _markingIndex < _images.length - 1
                    ? Icons.chevron_right
                    : Icons.check,
              ),
              tooltip: _markingIndex < _images.length - 1 ? '下一张' : '完成',
            ),
          ],
        ),
      ),
    );
  }

  // ── Practice view ───────────────────────────────────────────────

  Widget _buildPracticeView() {
    final targets = _framesWithTargets;
    if (targets.isEmpty) {
      return const Center(child: Text('没有可练习的步骤'));
    }

    final frame = targets[_practiceIndex];
    final target = frame.touchTarget;
    return SafeArea(
      child: Column(
        children: [
          // Progress bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                for (var i = 0; i < targets.length; i++)
                  Expanded(
                    child: Container(
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: i < _practiceIndex
                            ? Colors.green
                            : i == _practiceIndex
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey.shade300,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Instruction
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.touch_app, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '请点击图中标注的按钮位置（第 ${_practiceIndex + 1} 步）',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
          // Interactive image
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FrameStage(
                key: ValueKey('practice_${frame.index}_$_practiceIndex'),
                frame: frame,
                aspectRatio: 9 / 16,
                target: target,
                interactive: true,
                hitRadius: 0.14,
                onPracticeResult: (correct) {
                  _handlePracticeTap(frame.index, correct);
                },
              ),
            ),
          ),
          // Feedback
          Padding(
            padding: const EdgeInsets.all(16),
            child: _practiceIndex < _practiceCorrectCount
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 8),
                        Text(
                          '很好！点对了！',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(status)),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.isPicking,
    required this.isGenerating,
    required this.isDetecting,
    required this.hasImages,
    required this.markedCount,
    required this.totalCount,
    required this.onPickImages,
    required this.onStartMarking,
    required this.onDetectRedCircles,
    required this.onGenerateLesson,
    required this.onStartPractice,
  });

  final bool isPicking;
  final bool isGenerating;
  final bool isDetecting;
  final bool hasImages;
  final int markedCount;
  final int totalCount;
  final VoidCallback onPickImages;
  final VoidCallback onStartMarking;
  final VoidCallback onDetectRedCircles;
  final VoidCallback onGenerateLesson;
  final VoidCallback onStartPractice;

  @override
  Widget build(BuildContext context) {
    final busy = isPicking || isGenerating || isDetecting;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: busy ? null : onPickImages,
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(isPicking ? '选择中' : '选择截图'),
        ),
        FilledButton.tonalIcon(
          onPressed: busy || !hasImages ? null : onStartMarking,
          icon: const Icon(Icons.edit_location_alt),
          label: Text('标注位置 ($markedCount/$totalCount)'),
        ),
        FilledButton.tonalIcon(
          onPressed: busy || !hasImages ? null : onDetectRedCircles,
          icon: const Icon(Icons.auto_fix_high),
          label: Text(isDetecting ? '识别中' : '自动识别红圈'),
        ),
        const SizedBox(width: 4),
        FilledButton.tonalIcon(
          onPressed: busy || !hasImages ? null : onGenerateLesson,
          icon: const Icon(Icons.school),
          label: Text(isGenerating ? '生成中' : 'AI 生成教程'),
        ),
        FilledButton.icon(
          onPressed: busy || markedCount == 0 ? null : onStartPractice,
          icon: const Icon(Icons.play_circle),
          label: Text('开始练习 ($markedCount)'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade600,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _ImagePreviewPanel extends StatelessWidget {
  const _ImagePreviewPanel({
    required this.images,
    required this.selectedImage,
    required this.selectedIndex,
    required this.onSelectImage,
  });

  final List<VideoFrame> images;
  final VideoFrame selectedImage;
  final int selectedIndex;
  final ValueChanged<int> onSelectImage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('截图预览', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (selectedImage.touchTarget != null)
              Chip(
                avatar: const Icon(Icons.check_circle,
                    color: Colors.green, size: 16),
                label: Text(
                  selectedImage.touchTarget!.label ?? '已标注',
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: Colors.green.shade50,
              ),
          ],
        ),
        const SizedBox(height: 8),
        FrameStage(
          frame: selectedImage,
          aspectRatio: 9 / 16,
          target: selectedImage.touchTarget,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final frame = images[index];
              final selected = index == selectedIndex;
              final hasTarget = frame.touchTarget != null;
              return InkWell(
                onTap: () => onSelectImage(index),
                borderRadius: BorderRadius.circular(8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      alignment: Alignment.bottomLeft,
                      children: [
                        Image.memory(
                          frame.bytes,
                          width: 82,
                          height: 104,
                          fit: BoxFit.cover,
                        ),
                        if (hasTarget)
                          const Positioned(
                            top: 5,
                            right: 5,
                            child: Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 18,
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          color: Colors.black.withValues(alpha: 0.55),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
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
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(18),
        child: Center(child: Text('教程会在这里展示')),
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
  });

  final Lesson lesson;
  final int activeStepIndex;
  final VideoFrame? activeFrame;
  final bool isPlaying;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onTogglePlayback;
  final ValueChanged<int> onSelectStep;

  @override
  Widget build(BuildContext context) {
    final step = lesson.steps[activeStepIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(lesson.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(lesson.summary),
        const SizedBox(height: 12),
        if (activeFrame != null)
          FrameStage(
            frame: activeFrame!,
            aspectRatio: 9 / 16,
            target: step.action.target,
          ),
        const SizedBox(height: 12),
        Text(
          '${activeStepIndex + 1} / ${lesson.steps.length}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        Text(step.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(step.instruction, style: Theme.of(context).textTheme.bodyLarge),
        if (step.elderTip != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.tips_and_updates_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(step.elderTip!)),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: activeStepIndex == 0 ? null : onPrevious,
              icon: const Icon(Icons.chevron_left),
              tooltip: '上一步',
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: onTogglePlayback,
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              tooltip: isPlaying ? '暂停播放' : '播放教程',
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: activeStepIndex == lesson.steps.length - 1
                  ? null
                  : onNext,
              icon: const Icon(Icons.chevron_right),
              tooltip: '下一步',
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final indexed in lesson.steps.indexed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Text('${indexed.$2.order}')),
            title: Text(indexed.$2.title),
            subtitle: Text(indexed.$2.action.type.wireName),
            selected: indexed.$1 == activeStepIndex,
            onTap: () => onSelectStep(indexed.$1),
          ),
      ],
    );
  }
}
