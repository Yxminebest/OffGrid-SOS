import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../app/theme.dart';
import '../../models/user.dart';
import '../../services/app_notifications.dart';
import '../../services/chat_camera_service.dart';
import '../../services/chat_media_cache.dart';
import '../../services/chat_service.dart';
import '../../services/home_return_policy.dart';
import '../../services/location_service.dart';
import '../../services/network_service.dart';
import '../../services/unified_chat_service.dart';
import '../../widgets/location_actions.dart';
import '../../widgets/chat_location_preview.dart';
import '../../widgets/nearby_media_preview.dart';

class UnifiedConversationScreen extends StatefulWidget {
  const UnifiedConversationScreen({
    super.key,
    required this.me,
    required this.contact,
    this.service,
    this.caseId,
    this.initialDraft,
    this.gps = const LocationService(),
  });
  final AppUser me;
  final ChatContact contact;
  final UnifiedChatService? service;
  final String? caseId, initialDraft;
  final LocationService gps;
  @override
  State<UnifiedConversationScreen> createState() =>
      _UnifiedConversationScreenState();
}

class _UnifiedConversationScreenState extends State<UnifiedConversationScreen> {
  late final chat = widget.service ?? UnifiedChatService.instance;
  late final input = TextEditingController(text: widget.initialDraft);
  late final stream = chat.watchInbox(widget.me.id);
  late ChatContact contact = widget.contact;
  StreamSubscription<List<Map<String, dynamic>>>? _cloud;
  String? _subscribed;
  bool busy = false, _reading = false;
  @override
  void initState() {
    super.initState();
    chat.start(widget.me);
    chat.mesh.addListener(_changed);
    NetworkService.instance.online.addListener(_changed);
    AppNotifications.instance.activeThread =
        contact.device ?? contact.conversation;
    unawaited(chat.rememberPeers(widget.me.id));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _subscribe() {
    if (!mounted ||
        !widget.me.isMember ||
        !chat.online() ||
        contact.conversation == null ||
        _subscribed == contact.conversation) {
      return;
    }
    _subscribed = contact.conversation;
    unawaited(_cloud?.cancel());
    // Reuse the existing cloud reader and RLS; both transports feed this room.
    unawaited(() async {
      try {
        final c = await chat.resolve(widget.me, contact);
        final inbox = await ChatService.instance.watchInbox(widget.me.id).first;
        final conversation = inbox
            .where((v) => v.id == c.conversation)
            .firstOrNull;
        if (!mounted || conversation == null) return;
        _cloud = ChatService.instance.subscribeMessages(
          me: widget.me,
          conversation: conversation,
          onError: (_) {
            _subscribed = null;
          },
        );
      } catch (_) {
        _subscribed = null;
      }
    }());
  }

  @override
  void dispose() {
    chat.mesh.removeListener(_changed);
    NetworkService.instance.online.removeListener(_changed);
    AppNotifications.instance.activeThread = null;
    AppNotifications.instance.activeThreadAliases.clear();
    unawaited(_cloud?.cancel());
    input.dispose();
    super.dispose();
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } on ArgumentError catch (e) {
      _notice(e.message?.toString() ?? 'ข้อมูลที่ส่งไม่ถูกต้อง');
    } catch (_) {
      _notice('บันทึกไม่สำเร็จ กรุณาตรวจสิทธิ์และพื้นที่ว่าง แล้วลองอีกครั้ง');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _send() => _action(() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    await chat.send(widget.me, contact, text: text, caseId: widget.caseId);
    if (mounted) input.clear();
  });
  Future<void> _attach(String kind) => _action(() async {
    if (kind == 'location') {
      final point = await widget.gps.getLatestLocation();
      if (!mounted) return;
      if (point == null) {
        _notice('ยังไม่พบพิกัด เปิดตำแหน่งและลองใหม่ในที่โล่ง');
        return;
      }
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ส่งตำแหน่งของฉัน'),
          content: Text(
            '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}\n${point.qualityDescription}\n${point.isLastKnown ? 'พิกัดเก่า อาจไม่ใช่ตำแหน่งปัจจุบัน' : 'เวลาพิกัด: ${LocationActions.recordedAt(point.recordedAt)}'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ส่งตำแหน่ง'),
            ),
          ],
        ),
      );
      if (accepted == true && mounted) {
        await chat.send(
          widget.me,
          contact,
          location: point,
          caseId: widget.caseId,
        );
      }
      return;
    }
    if (kind == 'camera' || kind == 'record') {
      await ChatCameraService.instance.capture(
        widget.me,
        peerName: contact.name,
        unifiedDevice: contact.device,
        unifiedUser: contact.user,
        conversationId: contact.conversation,
        unified: true,
        video: kind == 'record',
        caseId: widget.caseId,
      );
      return;
    }
    final file = await ExternalActivity.run(
      () => kind == 'image'
          ? ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 2560,
              maxHeight: 2560,
              imageQuality: 92,
            )
          : ImagePicker().pickVideo(source: ImageSource.gallery),
    );
    if (file == null || !mounted) return;
    await chat.send(
      widget.me,
      contact,
      path: file.path,
      name: file.name,
      type: kind,
      caseId: widget.caseId,
    );
  });
  Future<void> _attachments() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    'ส่งไฟล์และตำแหน่ง',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('เก็บในเครื่องและรอส่งได้ · ไฟล์สูงสุด 25 MB'),
                ),
                for (final item in [
                  ('camera', Icons.photo_camera_outlined, 'ถ่ายรูป'),
                  ('image', Icons.photo_library_outlined, 'รูปภาพจากเครื่อง'),
                  ('location', Icons.location_on_outlined, 'ตำแหน่งของฉัน'),
                  ('video', Icons.video_library_outlined, 'วิดีโอจากเครื่อง'),
                  ('record', Icons.videocam_outlined, 'ถ่ายวิดีโอ'),
                ])
                  ListTile(
                    leading: Icon(item.$2),
                    title: Text(item.$3),
                    onTap: () => Navigator.pop(ctx, item.$1),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (kind != null && mounted) await _attach(kind);
  }

  Future<void> _read() async {
    if (_reading) return;
    _reading = true;
    try {
      if (contact.device != null) {
        await chat.mesh.chats.markRead(widget.me.id, contact.device!);
      }
      if (widget.me.isMember && contact.conversation != null && chat.online()) {
        await ChatService.instance.markRead(contact.conversation!);
        await ChatService.instance.refreshInbox(widget.me);
      }
    } catch (_) {
    } finally {
      _reading = false;
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<ChatInboxEntry>>(
    stream: stream,
    builder: (context, snapshot) {
      final entry = snapshot.data
          ?.where(
            (e) =>
                (contact.user != null && e.contact.user == contact.user) ||
                (contact.device != null && e.contact.device == contact.device),
          )
          .firstOrNull;
      if (entry != null) contact = entry.contact;
      if (ModalRoute.of(context)?.isCurrent ?? true) {
        AppNotifications.instance.activeThreadAliases
          ..clear()
          ..addAll([
            if (contact.device != null) contact.device!,
            if (contact.conversation != null) contact.conversation!,
            ...chat.mesh.reachablePeers
                .where((p) => contact.user != null && p.userId == contact.user)
                .map((p) => p.deviceId),
          ]);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _subscribe();
        if ((entry?.unread ?? 0) > 0) unawaited(_read());
      });
      final peer = contact.user == null
          ? (contact.device == null
                ? null
                : chat.mesh.peerForDevice(contact.device!))
          : chat.mesh.peerForUser(contact.user!);
      final status = peer != null
          ? (chat.mesh.isPeerRescueActive(peer.deviceId)
                ? 'หน่วยกู้ภัย · เชื่อมต่อแล้ว'
                : 'บุคคลใกล้เคียง · เชื่อมต่อแล้ว')
          : widget.me.isMember && contact.user != null && chat.online()
          ? 'ส่งผ่านอินเทอร์เน็ต · ประวัติเก็บในเครื่อง'
          : 'ออฟไลน์ · บันทึกข้อความรอส่งในเครื่อง';
      final list = entry?.messages ?? [];
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: MediaQuery.textScalerOf(
            context,
          ).scale(64).clamp(76, 240),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(contact.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                status,
                style: TextStyle(fontSize: 11, color: context.colors.muted),
                maxLines: 2,
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (snapshot.hasError)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('อ่านประวัติไม่ได้ ลองเปิดห้องนี้อีกครั้ง'),
                ),
              for (final transfer in chat.mesh.media.progress.values.where(
                (p) =>
                    p.incoming &&
                    p.fraction < 1 &&
                    (p.peer == contact.device || p.peer == peer?.deviceId),
              ))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'กำลังรับไฟล์ ${(transfer.fraction * 100).round()}%',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: transfer.fraction),
                    ],
                  ),
                ),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Text(
                          'เริ่มสนทนากับ ${contact.name}',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                        itemCount: list.length,
                        itemBuilder: (ctx, index) =>
                            _bubble(list[list.length - index - 1]),
                      ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(6),
                  child: Text(
                    'กำลังเตรียมไฟล์หรือตำแหน่ง…',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'แนบรูปหรือวิดีโอ',
                      onPressed: busy ? null : _attachments,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    Expanded(
                      child: TextField(
                        controller: input,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 4000,
                        decoration: const InputDecoration(
                          hintText: 'พิมพ์ข้อความ…',
                          counterText: '',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'ส่งข้อความ',
                      onPressed: busy ? null : _send,
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _bubble(ChatItem m) {
    final media = m.type == 'image' || m.type == 'video';
    final transfer = chat.mesh.media.progress[m.id];
    return Align(
      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .86,
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: m.mine ? context.colors.surfaceSoft : context.colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: context.colors.border),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onLongPress: () => Clipboard.setData(ClipboardData(text: m.text)),
              child: Padding(
                padding: EdgeInsets.all(media ? 8 : 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (media)
                      _UnifiedMedia(
                        key: ValueKey('media:${m.id}'),
                        owner: widget.me.id,
                        item: m,
                        online: chat.online(),
                      ),
                    if (m.type == 'location' &&
                        m.lat != null &&
                        m.lng != null) ...[
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on_outlined),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'ตำแหน่งที่แชร์',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${m.lat!.toStringAsFixed(6)}, ${m.lng!.toStringAsFixed(6)}',
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                        ),
                      ),
                      if (m.lastKnown)
                        const Text(
                          'พิกัดเก่า อาจไม่ใช่ตำแหน่งปัจจุบัน',
                          style: TextStyle(
                            color: Color(0xFF99601B),
                            fontSize: 12,
                          ),
                        ),
                      if (m.locationAt != null)
                        Text(
                          'เวลาพิกัด: ${LocationActions.recordedAt(m.locationAt!)}',
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ChatLocationPreview(
                        key: ValueKey('map:${m.id}'),
                        lat: m.lat!,
                        lng: m.lng!,
                        accuracy: m.accuracy,
                      ),
                      LocationActions(
                        latitude: m.lat!,
                        longitude: m.lng!,
                        accuracy: m.accuracy,
                      ),
                    ] else if (!media)
                      SelectableText(
                        m.text,
                        style: const TextStyle(fontSize: 16, height: 1.5),
                      ),
                    if (transfer != null && transfer.fraction < 1) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: transfer.fraction),
                      Text(
                        transfer.error != null
                            ? 'การส่งหยุดชั่วคราว จะลองเมื่อเชื่อมต่อได้'
                            : 'กำลังส่ง ${(transfer.fraction * 100).round()}%',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${m.at.toLocal().hour.toString().padLeft(2, '0')}:${m.at.toLocal().minute.toString().padLeft(2, '0')}${m.mine ? ' · ${switch (m.status) {
                              'delivered' => 'รับถึงเครื่องแล้ว',
                              'delivered_synced' => 'รับถึงเครื่องแล้ว · ซิงก์แล้ว',
                              'synced' => 'ซิงก์แล้ว',
                              'sent' => 'ส่งแล้ว · รอยืนยันรับ',
                              'error' => 'รอส่งใหม่',
                              _ => 'ค้างส่ง',
                            }}' : ''}',
                      style: TextStyle(
                        fontSize: 10,
                        color: context.colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnifiedMedia extends StatefulWidget {
  const _UnifiedMedia({
    super.key,
    required this.owner,
    required this.item,
    required this.online,
  });
  final String owner;
  final ChatItem item;
  final bool online;
  @override
  State<_UnifiedMedia> createState() => _UnifiedMediaState();
}

class _UnifiedMediaState extends State<_UnifiedMedia> {
  late Future<String?> path = _resolve();
  Future<String?> _resolve() async {
    final m = widget.item;
    if (m.path != null) return m.path;
    if (m.bytes?.isNotEmpty ?? false) {
      await ChatMediaCache.instance.put(widget.owner, m.id, m.bytes!);
    }
    final local = await ChatMediaCache.instance.local(widget.owner, m.id);
    if (local != null || !widget.online || m.mediaPath == null) return local;
    return ChatMediaCache.instance.resolve(
      widget.owner,
      m.id,
      () => ChatService.instance.signedMediaUrl(m.mediaPath),
    );
  }

  @override
  void didUpdateWidget(covariant _UnifiedMedia old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id ||
        old.item.path != widget.item.path ||
        old.item.mediaPath != widget.item.mediaPath ||
        old.online != widget.online) {
      path = _resolve();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: path,
    builder: (ctx, snapshot) {
      if (snapshot.data != null) {
        return NearbyMediaPreview(
          path: snapshot.data!,
          type: widget.item.type,
          name: widget.item.name,
        );
      }
      return Container(
        constraints: const BoxConstraints(minHeight: 180),
        width: 280,
        padding: const EdgeInsets.all(12),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.item.type == 'image'
                    ? Icons.image_outlined
                    : Icons.videocam_outlined,
                size: 40,
              ),
              const SizedBox(height: 8),
              Text(
                snapshot.connectionState == ConnectionState.waiting
                    ? 'กำลังเปิดไฟล์…'
                    : 'รอรับไฟล์ให้ครบ หรือเชื่อมต่อเพื่อดาวน์โหลด',
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: () => setState(() => path = _resolve()),
                child: const Text('ลองเปิดอีกครั้ง'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
