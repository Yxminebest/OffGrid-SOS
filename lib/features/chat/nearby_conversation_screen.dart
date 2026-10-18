import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../app/theme.dart';
import '../../data/repositories/nearby_chat_repository.dart';
import '../../models/user.dart';
import '../../services/app_notifications.dart';
import '../../services/nearby_mesh_service.dart';
import '../../services/chat_camera_service.dart';
import '../../widgets/nearby_media_preview.dart';

class NearbyConversationScreen extends StatefulWidget {
  const NearbyConversationScreen({
    super.key,
    required this.me,
    required this.peerId,
    required this.name,
    this.caseId,
    this.service,
    this.initialDraft,
  });
  final AppUser me;
  final NearbyMeshService? service;
  final String? initialDraft;
  final String peerId, name;
  final String? caseId;
  @override
  State<NearbyConversationScreen> createState() =>
      _NearbyConversationScreenState();
}

class _NearbyConversationScreenState extends State<NearbyConversationScreen> {
  late final input = TextEditingController(text: widget.initialDraft);
  final scroll = ScrollController();
  late final mesh = widget.service ?? NearbyMeshService.instance;
  late final repo = mesh.chats;
  late final records = repo.watchMessages(widget.me.id, widget.peerId);
  bool sending = false;
  @override
  void initState() {
    super.initState();
    mesh.addListener(_changed);
    AppNotifications.instance.activeThread = widget.peerId;
    unawaited(repo.markRead(widget.me.id, widget.peerId));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    mesh.removeListener(_changed);
    if (AppNotifications.instance.activeThread == widget.peerId) {
      AppNotifications.instance.activeThread = null;
    }
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (sending || input.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      await mesh.initializeForUser(widget.me);
      await mesh.sendDirect(
        target: widget.peerId,
        text: input.text.trim(),
        peerName: widget.name,
        caseId: widget.caseId,
      );
      input.clear();
      if (scroll.hasClients) {
        await scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกข้อความไม่ได้ กรุณาลองอีกครั้ง')),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> attach(String kind) async {
    if (sending) return;
    setState(() => sending = true);
    try {
      if (kind == 'camera') {
        await ChatCameraService.instance.capture(
          widget.me,
          peerId: widget.peerId,
          peerName: widget.name,
          caseId: widget.caseId,
        );
      } else {
        final picker = ImagePicker();
        final file = kind == 'image'
            ? await picker.pickImage(
                source: ImageSource.gallery,
                maxWidth: 1920,
                maxHeight: 1920,
                imageQuality: 85,
              )
            : await picker.pickVideo(source: ImageSource.gallery);
        if (file == null) return;
        if (!mounted) return;
        if (mesh.ownerId != widget.me.id) throw StateError('บัญชีเปลี่ยนแล้ว');
        await mesh.sendAttachment(
          target: widget.peerId,
          path: file.path,
          name: file.name,
          type: kind,
          peerName: widget.name,
          caseId: widget.caseId,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'แนบไฟล์ไม่ได้ กรุณาตรวจสิทธิ์และพื้นที่ว่าง ไฟล์ต้องไม่เกิน 25 MB',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> attachments() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('ส่งตรงโดยไม่ใช้อินเทอร์เน็ต · สูงสุด 25 MB'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('ถ่ายรูป'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('รูปภาพจากเครื่อง'),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('วิดีโอจากเครื่อง'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
      ),
    );
    if (kind != null && mounted) await attach(kind);
  }

  @override
  Widget build(BuildContext context) {
    final connected = mesh.peerForDevice(widget.peerId) != null;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              connected
                  ? 'Nearby • เชื่อมต่อแล้ว'
                  : 'Nearby • รอเชื่อมต่อเพื่อส่ง',
              style: TextStyle(fontSize: 12, color: context.colors.muted),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: context.colors.surfaceSoft,
              child: Text(
                connected
                    ? ((mesh.peerForDevice(widget.peerId)?.hops ?? 1) > 1
                          ? 'ส่งผ่านเครื่องตัวกลาง • เข้ารหัสข้อความ • ไม่ใช้อินเทอร์เน็ต'
                          : 'ส่งตรงถึงเครื่องที่จับคู่ ไม่ใช้อินเทอร์เน็ต')
                    : 'ข้อความจะเก็บในเครื่อง และส่งเมื่อจับคู่กับอุปกรณ์นี้อีกครั้ง',
                style: TextStyle(color: context.colors.muted, fontSize: 12),
              ),
            ),
            for (final transfer in mesh.media.progress.values.where(
              (p) => p.peer == widget.peerId && p.incoming,
            ))
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'กำลังรับไฟล์ ${(transfer.fraction * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 12),
                    ),
                    LinearProgressIndicator(value: transfer.fraction),
                  ],
                ),
              ),
            Expanded(
              child: StreamBuilder<List<Map<String, Object?>>>(
                stream: records,
                builder: (context, snapshot) {
                  final rows = (snapshot.data ?? [])
                      .where(
                        (r) =>
                            widget.caseId == null ||
                            ((r['envelope'] as Map)['data'] as Map)['caseId'] ==
                                widget.caseId,
                      )
                      .toList()
                      .reversed
                      .toList();
                  if (rows.any(
                    (r) => r['incoming'] == true && r['read'] != true,
                  )) {
                    unawaited(repo.markRead(widget.me.id, widget.peerId));
                  }
                  if (rows.isEmpty) {
                    return Center(
                      child: Text(
                        'เริ่มส่งข้อความถึง ${widget.name}',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: scroll,
                    reverse: true,
                    padding: const EdgeInsets.all(18),
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final row = rows[i];
                      final mine = row['incoming'] != true;
                      final env = row['envelope'] as Map;
                      final body = env['data'] as Map;
                      final transfer = mesh.media.progress[env['id']];
                      final isMedia = env['kind'] == 'media';
                      final at = DateTime.tryParse(
                        env['at']?.toString() ?? '',
                      )?.toLocal();
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * .82,
                          ),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: mine
                                ? context.colors.surfaceSoft
                                : context.colors.surface,
                            border: Border.all(color: context.colors.border),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isMedia && row['localPath'] is String)
                                NearbyMediaPreview(
                                  path: row['localPath'] as String,
                                  type: body['type'] as String,
                                  name: body['name'] as String,
                                )
                              else
                                Text(
                                  body['text']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.55,
                                  ),
                                ),
                              if (isMedia) ...[
                                Text(
                                  '${((body['size'] as num) / (1024 * 1024)).toStringAsFixed(1)} MB',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.colors.muted,
                                  ),
                                ),
                                if (transfer != null) ...[
                                  const SizedBox(height: 8),
                                  if (transfer.error == null)
                                    LinearProgressIndicator(
                                      value: transfer.fraction,
                                    ),
                                  Text(
                                    transfer.error ??
                                        'กำลังส่ง ${(transfer.fraction * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: context.colors.muted,
                                    ),
                                  ),
                                ],
                              ],
                              if (row['historical'] == true)
                                const Text(
                                  'ประวัติสำรองจากคลาวด์',
                                  style: TextStyle(fontSize: 10),
                                ),
                              const SizedBox(height: 5),
                              Text(
                                '${at == null ? '' : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'}${mine ? ' · ${switch (row['delivery']) {
                                        'delivered' => row['cloudState'] == 'synced' ? 'รับถึงเครื่องแล้ว • ซิงก์แล้ว' : 'รับถึงเครื่องแล้ว',
                                        'sent' => 'ส่งแล้ว · รอยืนยันรับ',
                                        _ => 'รอเชื่อมต่อ',
                                      }}' : ''}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: context.colors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'แนบรูปหรือวิดีโอ',
                    onPressed: sending ? null : attachments,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                  Expanded(
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 4000,
                      decoration: const InputDecoration(
                        hintText: 'ข้อความ Nearby',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'ส่งข้อความ',
                    onPressed: sending ? null : send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NearbyInbox extends StatelessWidget {
  const NearbyInbox({super.key, required this.me});
  final AppUser me;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: NearbyMeshService.instance,
    builder: (context, _) {
      final mesh = NearbyMeshService.instance;
      return StreamBuilder<List<NearbyThread>>(
        stream: mesh.chats.watchThreads(me.id),
        builder: (context, snapshot) {
          final threads = snapshot.data ?? [];
          final byId = {for (final t in threads) t.peerId: t};
          final connected = mesh.reachablePeers;
          final ids = {...connected.map((p) => p.deviceId), ...byId.keys};
          if (ids.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'จับคู่อุปกรณ์ในแท็บใกล้เคียง แล้วกลับมาแชทที่นี่ได้แม้ไม่มีอินเทอร์เน็ต',
                style: TextStyle(color: context.colors.muted, fontSize: 13),
              ),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final id in ids)
                Builder(
                  builder: (context) {
                    final peer = mesh.peerForDevice(id);
                    final t = byId[id];
                    final name = peer?.name ?? t?.name ?? 'คนใกล้เคียง';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: context.colors.surfaceSoft,
                        child: Icon(
                          peer == null
                              ? Icons.chat_bubble_outline_rounded
                              : Icons.bluetooth_connected_rounded,
                          color: context.colors.info,
                        ),
                      ),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        t?.preview ?? 'เริ่มแชทผ่าน Nearby',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: t != null && t.unread > 0
                          ? Badge(label: Text('${t.unread}'))
                          : Text(
                              peer == null ? 'ออฟไลน์' : 'Nearby',
                              style: TextStyle(
                                color: context.colors.muted,
                                fontSize: 11,
                              ),
                            ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => NearbyConversationScreen(
                            me: me,
                            peerId: id,
                            name: name,
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      );
    },
  );
}
