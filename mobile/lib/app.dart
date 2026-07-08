import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'generation/lesson_validator.dart';
import 'generation/mock_lesson_generator.dart';
import 'generation/model_client.dart';
import 'generation/prompt_builder.dart';
import 'generation/remote_multimodal_model_client.dart';
import 'models/lesson.dart';
import 'models/video_frame.dart';
import 'video/frame_extractor.dart';
import 'vision/touch_indicator_detector.dart';
import 'widgets/frame_stage.dart';

class VideoToLessonApp extends StatelessWidget {
  const VideoToLessonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '手机操作教程',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF25705A),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8F5),
        useMaterial3: true,
      ),
      home: VideoToLessonPage(modelClient: _buildModelClient()),
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

class VideoToLessonPage extends StatefulWidget {
  const VideoToLessonPage({
    super.key,
    this.imagePicker,
    this.frameExtractor = const FrameExtractor(),
    this.promptBuilder = const PromptBuilder(),
    this.modelClient = const MockLessonGenerator(),
    this.lessonValidator = const LessonValidator(),
    this.touchIndicatorDetector = const IsolateTouchIndicatorDetector(),
  });

  final ImagePicker? imagePicker;
  final FrameExtractor frameExtractor;
  final PromptBuilder promptBuilder;
  final ModelClient modelClient;
  final LessonValidator lessonValidator;
  final TouchIndicatorDetector touchIndicatorDetector;

  @override
  State<VideoToLessonPage> createState() => _VideoToLessonPageState();
}

class _VideoToLessonPageState extends State<VideoToLessonPage> {
  final _goalController = TextEditingController(text: '把视频里的手机操作讲成适合老人照做的步骤');
  VideoPlayerController? _videoController;
  SelectedVideo? _video;
  List<VideoFrame> _frames = [];
  Lesson? _lesson;
  int _selectedFrameIndex = 0;
  int _activeStepIndex = 0;
  Timer? _playTimer;
  bool _isPicking = false;
  bool _isExtracting = false;
  bool _isGenerating = false;
  bool _isDetectingTouches = false;
  String _status = '请选择一段手机操作视频';

  ImagePicker get _picker => widget.imagePicker ?? ImagePicker();

  @override
  void dispose() {
    _goalController.dispose();
    _videoController?.dispose();
    _playTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    setState(() {
      _isPicking = true;
      _status = '正在打开视频选择器';
    });

    try {
      final file = await _picker.pickVideo(source: ImageSource.gallery);
      if (file == null) {
        setState(() {
          _status = '未选择视频';
        });
        return;
      }

      final controller = VideoPlayerController.file(File(file.path));
      await controller.initialize();
      await _videoController?.dispose();

      setState(() {
        _videoController = controller;
        _video = SelectedVideo(
          path: file.path,
          name: _nameFromPath(file.path),
          mimeType: file.mimeType,
          duration: controller.value.duration,
          aspectRatio: controller.value.aspectRatio,
        );
        _frames = [];
        _lesson = null;
        _selectedFrameIndex = 0;
        _activeStepIndex = 0;
        _status = widget.modelClient.supportsDirectVideo
            ? '已选择视频，可以直接 AI 生成教程'
            : '已选择视频，可以抽取关键帧';
      });
    } catch (error) {
      setState(() {
        _status = '视频读取失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  Future<void> _extractFrames({bool detectTouches = true}) async {
    final video = _video;
    if (video == null) {
      return;
    }

    setState(() {
      _isExtracting = true;
      _status = '正在抽取关键帧';
      _lesson = null;
      _selectedFrameIndex = 0;
      _activeStepIndex = 0;
    });

    try {
      final frames = await widget.frameExtractor.extract(video);
      setState(() {
        _frames = frames;
        _selectedFrameIndex = 0;
        _status = frames.isEmpty
            ? '未抽到关键帧'
            : '已抽取 ${frames.length} 个关键帧，正在自动识别触摸点';
      });
      if (frames.isNotEmpty && detectTouches) {
        await _detectTouchTargets();
      }
    } catch (error) {
      setState(() {
        _status = '抽帧失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isExtracting = false;
        });
      }
    }
  }

  Future<void> _generateLesson() async {
    final video = _video;
    if (video == null) {
      return;
    }

    if (_frames.isEmpty && !widget.modelClient.supportsDirectVideo) {
      await _extractFrames();
      if (_frames.isEmpty) {
        return;
      }
    }

    setState(() {
      _isGenerating = true;
      _status = widget.modelClient.supportsDirectVideo
          ? '正在上传视频给 AI 生成教程'
          : '正在生成模拟教程';
    });

    try {
      if (_frames.isEmpty && widget.modelClient.supportsDirectVideo) {
        await _extractFrames(detectTouches: false);
        if (mounted) {
          setState(() {
            _isGenerating = true;
            _status = '正在上传视频给 AI 生成教程';
          });
        }
      }
      final goal = _goalController.text.trim();
      final prompt = widget.promptBuilder.build(
        frames: _frames,
        video: video,
        audience: 'elderly smartphone user',
        goal: goal,
      );
      final lesson = await widget.modelClient.generateLessonJson(
        frames: _frames,
        video: video,
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

  Future<void> _detectTouchTargets() async {
    if (_frames.isEmpty) {
      return;
    }

    setState(() {
      _isDetectingTouches = true;
      _status = '正在识别录屏里的触摸圆点';
    });

    try {
      final detections = await widget.touchIndicatorDetector.detect(_frames);
      final detectionsByFrame = {
        for (final detection in detections) detection.frameIndex: detection,
      };
      setState(() {
        _frames = [
          for (final frame in _frames)
            detectionsByFrame.containsKey(frame.index)
                ? frame.copyWith(
                    touchTarget: detectionsByFrame[frame.index]!.target,
                  )
                : frame.copyWith(clearTouchTarget: true),
        ];
        _lesson = null;
        _activeStepIndex = 0;
        _status = detections.isEmpty
            ? '未识别到触摸点，可手动点选校准'
            : '已自动识别 ${detections.length} 个触摸点，可直接生成教程';
      });
    } catch (error) {
      setState(() {
        _status = '识别触摸点失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isDetectingTouches = false;
        });
      }
    }
  }

  void _showStep(int index) {
    final lesson = _lesson;
    if (lesson == null) {
      return;
    }
    setState(() {
      _activeStepIndex = index.clamp(0, lesson.steps.length - 1);
    });
  }

  void _selectFrame(int index) {
    setState(() {
      _selectedFrameIndex = index.clamp(0, _frames.length - 1);
    });
  }

  void _markFrameTarget(Offset relativePosition) {
    if (_frames.isEmpty) {
      return;
    }
    final frame = _frames[_selectedFrameIndex];
    final updatedFrame = frame.copyWith(
      touchTarget: RelativeTarget(
        x: relativePosition.dx,
        y: relativePosition.dy,
        width: 0.18,
        height: 0.09,
        label: '真实点击位置',
      ),
    );
    setState(() {
      _frames = [
        for (final item in _frames)
          if (item.index == frame.index) updatedFrame else item,
      ];
      _lesson = null;
      _activeStepIndex = 0;
      _status = '已标注第 ${frame.index + 1} 帧，可继续标注或生成教程';
    });
  }

  void _clearFrameTarget() {
    if (_frames.isEmpty) {
      return;
    }
    final frame = _frames[_selectedFrameIndex];
    setState(() {
      _frames = [
        for (final item in _frames)
          if (item.index == frame.index)
            frame.copyWith(clearTouchTarget: true)
          else
            item,
      ];
      _lesson = null;
      _activeStepIndex = 0;
      _status = '已清除第 ${frame.index + 1} 帧标注';
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

  @override
  Widget build(BuildContext context) {
    final lesson = _lesson;
    final activeStep = lesson == null ? null : lesson.steps[_activeStepIndex];
    final activeFrame = activeStep == null || _frames.isEmpty
        ? null
        : _frames[activeStep.frameIndex.clamp(0, _frames.length - 1)];
    final selectedFrame = _frames.isEmpty
        ? null
        : _frames[_selectedFrameIndex.clamp(0, _frames.length - 1)];
    final markedCount = _frames
        .where((frame) => frame.touchTarget != null)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('手机操作教程生成器'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: Text('${_frames.length} 帧')),
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
              isExtracting: _isExtracting,
              isGenerating: _isGenerating,
              isDetectingTouches: _isDetectingTouches,
              supportsDirectVideo: widget.modelClient.supportsDirectVideo,
              hasVideo: _video != null,
              hasFrames: _frames.isNotEmpty,
              markedCount: markedCount,
              onPickVideo: _pickVideo,
              onExtractFrames: _extractFrames,
              onDetectTouches: _detectTouchTargets,
              onGenerateLesson: _generateLesson,
            ),
            const SizedBox(height: 16),
            if (_videoController != null)
              _VideoPreview(controller: _videoController!),
            if (_frames.isNotEmpty) ...[
              const SizedBox(height: 16),
              if (widget.modelClient.supportsDirectVideo)
                _FramePreviewPanel(frames: _frames)
              else
                _FrameAnnotationPanel(
                  frames: _frames,
                  selectedFrame: selectedFrame!,
                  selectedFrameIndex: _selectedFrameIndex,
                  aspectRatio: _video?.aspectRatio ?? 9 / 16,
                  onSelectFrame: _selectFrame,
                  onMarkTarget: _markFrameTarget,
                  onClearTarget: _clearFrameTarget,
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
                aspectRatio: _video?.aspectRatio ?? 9 / 16,
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

  String _nameFromPath(String path) {
    final parts = path.split(Platform.pathSeparator);
    return parts.isEmpty ? 'selected-video.mp4' : parts.last;
  }
}

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
    required this.isExtracting,
    required this.isGenerating,
    required this.isDetectingTouches,
    required this.supportsDirectVideo,
    required this.hasVideo,
    required this.hasFrames,
    required this.markedCount,
    required this.onPickVideo,
    required this.onExtractFrames,
    required this.onDetectTouches,
    required this.onGenerateLesson,
  });

  final bool isPicking;
  final bool isExtracting;
  final bool isGenerating;
  final bool isDetectingTouches;
  final bool supportsDirectVideo;
  final bool hasVideo;
  final bool hasFrames;
  final int markedCount;
  final VoidCallback onPickVideo;
  final VoidCallback onExtractFrames;
  final VoidCallback onDetectTouches;
  final VoidCallback onGenerateLesson;

  @override
  Widget build(BuildContext context) {
    final busy =
        isPicking || isExtracting || isGenerating || isDetectingTouches;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: busy ? null : onPickVideo,
          icon: const Icon(Icons.video_library),
          label: Text(isPicking ? '选择中' : '选择视频'),
        ),
        FilledButton.tonalIcon(
          onPressed: busy || !hasVideo || supportsDirectVideo
              ? null
              : onExtractFrames,
          icon: const Icon(Icons.auto_awesome_motion),
          label: Text(isExtracting ? '抽帧中' : '抽取关键帧'),
        ),
        FilledButton.tonalIcon(
          onPressed: busy || !hasFrames || supportsDirectVideo
              ? null
              : onDetectTouches,
          icon: const Icon(Icons.touch_app),
          label: Text(isDetectingTouches ? '识别中' : '识别触摸点'),
        ),
        FilledButton.tonalIcon(
          onPressed: busy || !hasVideo ? null : onGenerateLesson,
          icon: const Icon(Icons.school),
          label: Text(
            isGenerating
                ? '生成中'
                : supportsDirectVideo
                ? 'AI 生成教程'
                : '生成教程 ($markedCount)',
          ),
        ),
      ],
    );
  }
}

class _VideoPreview extends StatelessWidget {
  const _VideoPreview({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('视频预览', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
      ],
    );
  }
}

class _FramePreviewPanel extends StatelessWidget {
  const _FramePreviewPanel({required this.frames});

  final List<VideoFrame> frames;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AI 分析预览帧', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: frames.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final frame = frames[index];
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  alignment: Alignment.bottomLeft,
                  children: [
                    Image.memory(
                      frame.bytes,
                      width: 82,
                      height: 104,
                      fit: BoxFit.cover,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      color: Colors.black.withValues(alpha: 0.55),
                      child: Text(
                        '${(frame.time.inMilliseconds / 1000).toStringAsFixed(1)}s',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FrameAnnotationPanel extends StatelessWidget {
  const _FrameAnnotationPanel({
    required this.frames,
    required this.selectedFrame,
    required this.selectedFrameIndex,
    required this.aspectRatio,
    required this.onSelectFrame,
    required this.onMarkTarget,
    required this.onClearTarget,
  });

  final List<VideoFrame> frames;
  final VideoFrame selectedFrame;
  final int selectedFrameIndex;
  final double aspectRatio;
  final ValueChanged<int> onSelectFrame;
  final ValueChanged<Offset> onMarkTarget;
  final VoidCallback onClearTarget;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '标注真实操作位置',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: selectedFrame.touchTarget == null
                  ? null
                  : onClearTarget,
              icon: const Icon(Icons.backspace_outlined),
              label: const Text('清除'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FrameStage(
          frame: selectedFrame,
          aspectRatio: aspectRatio,
          target: selectedFrame.touchTarget,
          onTapRelative: onMarkTarget,
        ),
        const SizedBox(height: 8),
        Text(
          selectedFrame.touchTarget == null
              ? '未识别到时，可在上方画面点一下校准'
              : '${selectedFrame.touchTarget!.label ?? '触摸点'}：x=${selectedFrame.touchTarget!.x.toStringAsFixed(2)}, y=${selectedFrame.touchTarget!.y.toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: frames.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final frame = frames[index];
              final selected = index == selectedFrameIndex;
              return InkWell(
                onTap: () => onSelectFrame(index),
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
                        if (frame.touchTarget != null)
                          const Positioned(
                            top: 5,
                            right: 5,
                            child: Icon(
                              Icons.check_circle,
                              color: Colors.lightGreenAccent,
                              size: 22,
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          color: Colors.black.withValues(alpha: 0.55),
                          child: Text(
                            '${(frame.time.inMilliseconds / 1000).toStringAsFixed(1)}s',
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
    required this.aspectRatio,
    required this.isPlaying,
    required this.onPrevious,
    required this.onNext,
    required this.onTogglePlayback,
    required this.onSelectStep,
  });

  final Lesson lesson;
  final int activeStepIndex;
  final VideoFrame? activeFrame;
  final double aspectRatio;
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
            aspectRatio: aspectRatio,
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
