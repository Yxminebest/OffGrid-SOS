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
                appBar: AppBar(title: Text(name)),
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
            child: Image.file(
              File(path),
              height: 180,
              width: 240,
              fit: BoxFit.cover,
              cacheWidth: 720,
              errorBuilder: (_, _, _) => const Padding(
                padding: EdgeInsets.all(16),
                child: Text('เปิดรูปไม่ได้ ไฟล์อาจถูกลบ'),
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
      Text(
        name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
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

class _LocalVideoState extends State<_LocalVideo> {
  late final player = VideoPlayerController.file(File(widget.path));
  bool ready = false, failed = false;
  @override
  void initState() {
    super.initState();
    player.addListener(_changed);
    player
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => ready = true);
        })
        .catchError((Object _) {
          if (mounted) setState(() => failed = true);
        });
  }

  void _changed() {
    if (mounted && ready) setState(() {});
  }

  @override
  void dispose() {
    player.removeListener(_changed);
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.name)),
    body: failed || player.value.hasError
        ? const Center(child: Text('เปิดวิดีโอไม่ได้ รูปแบบไฟล์อาจไม่รองรับ'))
        : !ready
        ? const Center(child: CircularProgressIndicator())
        : Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: player.value.aspectRatio,
                  child: VideoPlayer(player),
                ),
                VideoProgressIndicator(player, allowScrubbing: true),
                IconButton(
                  tooltip: player.value.isPlaying
                      ? 'หยุดชั่วคราว'
                      : 'เล่นวิดีโอ',
                  onPressed: () =>
                      player.value.isPlaying ? player.pause() : player.play(),
                  icon: Icon(
                    player.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
              ],
            ),
          ),
  );
}
