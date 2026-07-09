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
import 'screens/ui_practice_page.dart';
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
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
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
  });

  final ImagePicker? imagePicker;
  final PromptBuilder promptBuilder;
  final ModelClient modelClient;
  final LessonValidator lessonValidator;

  @override
  State<ScreenshotLessonPage> createState() => _ScreenshotLessonPageState();
}

class _ScreenshotLessonPageState extends State<ScreenshotLessonPage> {
  final _goalController = TextEditingController(text: '把截图里的手机操作讲成适合老人照做的步骤');

  List<VideoFrame> _images = [];
  Lesson? _lesson;
  int _selectedImageIndex = 0;
  int _activeStepIndex = 0;
  bool _isPicking = false;
  bool _isGenerating = false;
  Timer? _playTimer;
  String _status = '请选择手机操作截图，AI 会直接根据图片生成教程';

  ImagePicker get _picker => widget.imagePicker ?? ImagePicker();

  @override
  void dispose() {
    _goalController.dispose();
    _playTimer?.cancel();
    super.dispose();
  }

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
        _status = '已选择 ${frames.length} 张截图，可以生成教程';
      });
    } catch (error) {
      setState(() => _status = '图片读取失败：$error');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _generateLesson() async {
    if (_images.isEmpty) return;
    _stopPlayback();
    setState(() {
      _isGenerating = true;
      _status = 'AI 正在读取截图并生成教程...';
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
        _selectedImageIndex = lesson.steps.isEmpty
            ? 0
            : lesson.steps.first.frameIndex;
        _status = '教程已生成';
      });
    } catch (error) {
      setState(() => _status = '生成失败：$error');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _startSimulation() async {
    if (_images.isEmpty) return;
    _stopPlayback();
    setState(() {
      _isGenerating = true;
      _status = 'AI 正在生成仿真界面...';
    });

    try {
      final result = await widget.modelClient.generateUI(
        frames: _images,
        markedPositions: _images.map((_) => (x: 0.5, y: 0.5)).toList(),
        goal: _goalController.text.trim(),
      );
      if (result == null || !mounted) {
        setState(() {
          _isGenerating = false;
          _status = '生成失败，请重试';
        });
        return;
      }

      setState(() => _isGenerating = false);

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UIPracticePage(
            html: result.html,
            title: result.title,
            targetCount: _images.length,
          ),
        ),
      );
    } catch (error) {
      setState(() {
        _isGenerating = false;
        _status = '生成失败：$error';
      });
    }
  }

  void _selectImage(int index) {
    setState(() => _selectedImageIndex = index.clamp(0, _images.length - 1));
  }

  void _showStep(int index) {
    final lesson = _lesson;
    if (lesson == null || lesson.steps.isEmpty) return;
    final nextIndex = index.clamp(0, lesson.steps.length - 1);
    final frameIndex = lesson.steps[nextIndex].frameIndex.clamp(
      0,
      _images.length - 1,
    );
    setState(() {
      _activeStepIndex = nextIndex;
      _selectedImageIndex = frameIndex;
    });
  }

  void _toggleLessonPlayback() {
    if (_playTimer != null) {
      _stopPlayback();
      return;
    }
    final lesson = _lesson;
    if (lesson == null || lesson.steps.isEmpty) return;
    _playTimer = Timer.periodic(const Duration(seconds: 3), (_) {
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

  @override
  Widget build(BuildContext context) {
    final lesson = _lesson;
    final selectedImage = _images.isEmpty
        ? null
        : _images[_selectedImageIndex.clamp(0, _images.length - 1)];
    final activeStep = lesson == null || lesson.steps.isEmpty
        ? null
        : lesson.steps[_activeStepIndex.clamp(0, lesson.steps.length - 1)];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '长辈学手机',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(child: _CountChip(count: _images.length)),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _StatusPanel(status: _status),
            const SizedBox(height: 16),
            _GoalField(controller: _goalController),
            const SizedBox(height: 16),
            _ActionBar(
              isBusy: _isPicking || _isGenerating,
              hasImages: _images.isNotEmpty,
              onPickImages: _pickImages,
              onGenerateLesson: _generateLesson,
              onStartSimulation: _startSimulation,
            ),
            if (selectedImage != null) ...[
              const SizedBox(height: 22),
              _ImagePreviewPanel(
                images: _images,
                selectedImage: selectedImage,
                selectedIndex: _selectedImageIndex,
                activeStep: activeStep,
                onSelectImage: _selectImage,
              ),
            ],
            const SizedBox(height: 22),
            if (lesson == null)
              const _EmptyLessonPanel()
            else
              _LessonPanel(
                lesson: lesson,
                activeStepIndex: _activeStepIndex,
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
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count 张',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.55),
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

class _GoalField extends StatelessWidget {
  const _GoalField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: 2,
      maxLines: 3,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: '学习目标',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.isBusy,
    required this.hasImages,
    required this.onPickImages,
    required this.onGenerateLesson,
    required this.onStartSimulation,
  });

  final bool isBusy;
  final bool hasImages;
  final VoidCallback onPickImages;
  final VoidCallback onGenerateLesson;
  final VoidCallback onStartSimulation;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: isBusy ? null : onPickImages,
          icon: const Icon(Icons.photo_library_outlined, size: 18),
          label: const Text(
            '选择截图',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: isBusy || !hasImages ? null : onGenerateLesson,
          icon: isBusy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.school_outlined, size: 18),
          label: const Text('生成教程'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: isBusy || !hasImages ? null : onStartSimulation,
          icon: const Icon(Icons.widgets_outlined, size: 18),
          label: const Text(
            '仿真练习',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
    required this.activeStep,
    required this.onSelectImage,
  });

  final List<VideoFrame> images;
  final VideoFrame selectedImage;
  final int selectedIndex;
  final LessonStep? activeStep;
  final ValueChanged<int> onSelectImage;

  @override
  Widget build(BuildContext context) {
    final target = activeStep?.frameIndex == selectedImage.index
        ? activeStep?.action.target
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '截图预览',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        FrameStage(
          key: ValueKey(
            'preview_${selectedImage.index}_${target?.x}_${target?.y}',
          ),
          frame: selectedImage,
          aspectRatio: 9 / 16,
          target: target,
          buttonLabel: activeStep?.title,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final image = images[index];
              final selected = index == selectedIndex;
              return GestureDetector(
                onTap: () => onSelectImage(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(image.bytes, fit: BoxFit.cover),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            color: Colors.black.withValues(alpha: 0.48),
                            child: Text(
                              '${index + 1}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(Icons.menu_book_outlined),
          SizedBox(width: 12),
          Expanded(child: Text('教程会在这里展示')),
        ],
      ),
    );
  }
}

class _LessonPanel extends StatelessWidget {
  const _LessonPanel({
    required this.lesson,
    required this.activeStepIndex,
    required this.isPlaying,
    required this.onPrevious,
    required this.onNext,
    required this.onTogglePlayback,
    required this.onSelectStep,
  });

  final Lesson lesson;
  final int activeStepIndex;
  final bool isPlaying;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onTogglePlayback;
  final ValueChanged<int> onSelectStep;

  @override
  Widget build(BuildContext context) {
    final steps = lesson.steps;
    final activeStep = steps[activeStepIndex.clamp(0, steps.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                lesson.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton.filledTonal(
              onPressed: onTogglePlayback,
              icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
              tooltip: isPlaying ? '暂停播放' : '播放教程',
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(lesson.summary, style: TextStyle(color: Colors.grey.shade700)),
        const SizedBox(height: 14),
        _ActiveStepCard(
          step: activeStep,
          index: activeStepIndex,
          total: steps.length,
          onPrevious: onPrevious,
          onNext: onNext,
        ),
        const SizedBox(height: 14),
        for (final step in steps)
          _StepTile(
            step: step,
            selected: step.order - 1 == activeStepIndex,
            onTap: () => onSelectStep(step.order - 1),
          ),
      ],
    );
  }
}

class _ActiveStepCard extends StatelessWidget {
  const _ActiveStepCard({
    required this.step,
    required this.index,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final LessonStep step;
  final int index;
  final int total;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '第 ${index + 1} 步 / 共 $total 步',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            step.instruction,
            style: const TextStyle(fontSize: 16, height: 1.5),
          ),
          if (step.elderTip != null && step.elderTip!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              step.elderTip!,
              style: TextStyle(color: Colors.grey.shade700, height: 1.4),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: index > 0 ? onPrevious : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('上一步'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: index < total - 1 ? onNext : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: const Text('下一步'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.step,
    required this.selected,
    required this.onTap,
  });

  final LessonStep step;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        selected: selected,
        selectedTileColor: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.55),
        tileColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: CircleAvatar(radius: 16, child: Text('${step.order}')),
        title: Text(
          step.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          step.instruction,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(_iconForAction(step.action.type)),
      ),
    );
  }

  IconData _iconForAction(LessonActionType type) {
    switch (type) {
      case LessonActionType.tap:
        return Icons.touch_app_outlined;
      case LessonActionType.longPress:
        return Icons.ads_click_outlined;
      case LessonActionType.swipe:
        return Icons.swipe_outlined;
      case LessonActionType.type:
        return Icons.keyboard_outlined;
      case LessonActionType.wait:
        return Icons.hourglass_empty_rounded;
      case LessonActionType.observe:
        return Icons.visibility_outlined;
    }
  }
}
