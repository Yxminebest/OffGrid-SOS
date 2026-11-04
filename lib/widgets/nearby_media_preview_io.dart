import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class NearbyMediaPreview extends StatelessWidget {
  const NearbyMediaPreview({
    super.key,
    required this.path,
    required this.type,
    required this.name,
  });
  final String path, type, name;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (type == 'image')
        InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('รูปภาพ')),
                body: Center(
                  child: InteractiveViewer(
                    child: Image.file(
                      File(path),
                      errorBuilder: (_, _, _) =>
                          const Text('เปิดรูปไม่ได้ ไฟล์อาจถูกลบ'),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340, maxHeight: 440),
              child: Image.file(
                File(path),
                width: 340,
                fit: BoxFit.contain,
                cacheWidth: 1440,
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('เปิดรูปไม่ได้ ไฟล์อาจถูกลบ'),
                ),
              ),
            ),
          ),
        )
      else
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => _LocalVideo(path: path, name: name),
            ),
          ),
          icon: const Icon(Icons.play_circle_outline_rounded),
          label: const Text('เล่นวิดีโอในเครื่อง'),
        ),
      const SizedBox(height: 6),
      Tooltip(
        message: name,
        child: Text(
          type == 'image' ? 'รูปภาพ' : 'วิดีโอ',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    ],
  );
}

class _LocalVideo extends StatefulWidget {
  const _LocalVideo({required this.path, required this.name});
  final String path, name;
  @override
  State<_LocalVideo> createState() => _LocalVideoState();
}

class _LocalVideoState extends State<_LocalVideo> with WidgetsBindingObserver {
  late final player = VideoPlayerController.file(File(widget.path));
  bool failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await player.initialize().timeout(const Duration(seconds: 20));
      if (!mounted) return;
      await player.play();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) player.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('วิดีโอ')),
    body: SafeArea(
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: player,
        builder: (context, value, _) {
          if (failed || value.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'เล่นวิดีโอไม่ได้ ไฟล์อาจไม่สมบูรณ์หรือเครื่องไม่รองรับรูปแบบนี้',
                ),
              ),
            );
          }
          if (!value.isInitialized) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: value.aspectRatio,
                    child: VideoPlayer(player),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: VideoProgressIndicator(player, allowScrubbing: true),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: value.isPlaying ? 'หยุดชั่วคราว' : 'เล่นวิดีโอ',
                    iconSize: 36,
                    onPressed: () async {
                      if (value.isPlaying) {
                        await player.pause();
                      } else {
                        if (value.position >= value.duration) {
                          await player.seekTo(Duration.zero);
                        }
                        await player.play();
                      }
                    },
                    icon: Icon(
                      value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  Text('${_time(value.position)} / ${_time(value.duration)}'),
                  if (value.isBuffering)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );

  String _time(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
}
