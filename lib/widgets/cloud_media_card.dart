import 'package:flutter/material.dart';
import '../data/models/local_message_record.dart';
import '../services/chat_media_cache.dart';
import '../services/chat_service.dart';
import '../services/network_service.dart';
import 'nearby_media_preview.dart';

class CloudMediaCard extends StatefulWidget {
  const CloudMediaCard({super.key, required this.message});
  final LocalMessageRecord message;
  @override
  State<CloudMediaCard> createState() => _CloudMediaCardState();
}

class _CloudMediaCardState extends State<CloudMediaCard> {
  late Future<String?> file = load();
  Future<String?> load() async {
    final m = widget.message;
    final cache = ChatMediaCache.instance;
    final existing = await cache.local(m.ownerLocalId, m.id);
    if (existing != null) return existing;
    if (m.mediaBytes?.isNotEmpty == true) {
      await cache.put(m.ownerLocalId, m.id, m.mediaBytes!);
      return cache.local(m.ownerLocalId, m.id);
    }
    return cache.resolve(
      m.ownerLocalId,
      m.id,
      () => ChatService.instance.signedMediaUrl(m.mediaPath),
    );
  }

  @override
  void initState() {
    super.initState();
    NetworkService.instance.online.addListener(changed);
  }

  void changed() {
    if (mounted && NetworkService.instance.online.value) {
      setState(() => file = load());
    }
  }

  @override
  void didUpdateWidget(CloudMediaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.mediaPath != widget.message.mediaPath) {
      file = load();
    }
  }

  @override
  void dispose() {
    NetworkService.instance.online.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: file,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return NearbyMediaPreview(
          path: snapshot.data!,
          type: widget.message.messageType,
          name: widget.message.mediaName ?? 'ไฟล์แนบ',
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.all(18),
          child: Text('กำลังเตรียมไฟล์ไว้ดูออฟไลน์…'),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_download_outlined),
          Text(
            snapshot.hasError
                ? 'บันทึกหรือดาวน์โหลดไฟล์ไม่สำเร็จ'
                : widget.message.mediaPath == null
                ? 'ไฟล์รออัปโหลด · ยังไม่พบไฟล์ในเครื่อง'
                : 'ยังไม่ได้ดาวน์โหลดไฟล์ไว้ในเครื่อง',
          ),
          Text(
            snapshot.hasError
                ? 'ตรวจพื้นที่ว่างและการเชื่อมต่อ แล้วลองอีกครั้ง'
                : 'เชื่อมต่ออินเทอร์เน็ตแล้วกดดาวน์โหลด เพื่อเปิดดูออฟไลน์ครั้งถัดไป',
            style: const TextStyle(fontSize: 12),
          ),
          TextButton(
            onPressed: () => setState(() => file = load()),
            child: const Text('ดาวน์โหลด / ลองอีกครั้ง'),
          ),
        ],
      );
    },
  );
}
