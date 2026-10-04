import 'dart:async';

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:video_player/video_player.dart';

import '../../app/theme.dart';

import '../../data/models/local_chat_conversation.dart';

import '../../data/models/local_message_record.dart';

import '../../data/repositories/message_repository.dart';

import '../../models/user.dart';

import '../../services/chat_service.dart';

import '../../services/location_service.dart';

import '../../services/sync_service.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,

    required this.me,

    required this.conversation,
  });

  final AppUser me;

  final LocalChatConversation conversation;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  static const int _maxAttachmentBytes = 100 * 1024 * 1024;

  final MessageRepository _messages = MessageRepository();

  final TextEditingController _text = TextEditingController();

  final ScrollController _scroll = ScrollController();

  StreamSubscription<List<Map<String, dynamic>>>? _cloudSubscription;

  Timer? _typingDebounce;

  bool _sending = false;

  LocalMessageRecord? _replyingTo;

  @override
  void initState() {
    super.initState();

    if (widget.me.isMember) {
      _cloudSubscription = ChatService.instance.subscribeMessages(
        me: widget.me,

        conversation: widget.conversation,

        onError: (error) {
          if (!mounted) return;

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Realtime chat: $error')));
        },
      );

      unawaited(_markReadBestEffort());
    }
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();

    _cloudSubscription?.cancel();

    if (widget.me.isMember) {
      unawaited(_setTypingBestEffort(false));
    }

    _text.dispose();

    _scroll.dispose();

    super.dispose();
  }

  Future<void> _setTypingBestEffort(bool isTyping) async {
    if (!widget.me.isMember) return;

    try {
      await ChatService.instance.setTyping(widget.conversation.id, isTyping);
    } catch (_) {
      // Typing is ephemeral presence only.
      // Losing the network must never make a message look failed.
    }
  }

  Future<void> _syncBestEffort() async {
    if (!widget.me.isMember) return;

    try {
      await SyncService.instance.syncNow();
    } catch (_) {
      // Local data is already stored and queued.
      // The sync engine will retry when connectivity returns.
    }
  }

  Future<void> _markReadBestEffort() async {
    if (!widget.me.isMember) return;

    try {
      await ChatService.instance.markRead(widget.conversation.id);
    } catch (_) {
      // Read receipts are best-effort while offline.
    }
  }

  void _typingChanged(String value) {
    if (!widget.me.isMember) return;

    _typingDebounce?.cancel();

    unawaited(_setTypingBestEffort(value.trim().isNotEmpty));

    _typingDebounce = Timer(const Duration(seconds: 6), () {
      unawaited(_setTypingBestEffort(false));
    });
  }

  Future<void> _sendText() async {
    final value = _text.text.trim();

    if (value.isEmpty || _sending) return;

    setState(() => _sending = true);

    try {
      await _messages.create(
        user: widget.me,

        conversationId: widget.conversation.id,

        content: value,

        replyToId: _replyingTo?.id,
      );

      _text.clear();

      if (mounted) {
        setState(() => _replyingTo = null);
      }

      _scrollToBottom();

      if (widget.me.isMember) {
        unawaited(_setTypingBestEffort(false));

        unawaited(_syncBestEffort());
      }
    } catch (e) {
      _show('บันทึกข้อความลงเครื่องไม่สำเร็จ: $e', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAttachment(String kind) async {
    final type = switch (kind) {
      'image' => FileType.image,

      'video' => FileType.video,

      'audio' => FileType.audio,

      _ => FileType.any,
    };

    final file = await FilePicker.pickFile(type: type);

    if (file == null) return;

    final length = file.lengthSync() ?? await file.length();

    if (length == null) {
      _show('ไม่สามารถตรวจสอบขนาดไฟล์ได้', error: true);

      return;
    }

    if (length > _maxAttachmentBytes) {
      _show('ไฟล์ต้องมีขนาดไม่เกิน 100 MB', error: true);

      return;
    }

    try {
      final bytes = await file.readAsBytes();

      final mime = _mimeFor(file.name, kind);

      await _messages.create(
        user: widget.me,

        conversationId: widget.conversation.id,

        type: kind,

        content: _attachmentLabel(kind, file.name),

        mediaName: file.name,

        mediaMime: mime,

        mediaBytes: bytes,

        replyToId: _replyingTo?.id,
      );

      if (mounted) setState(() => _replyingTo = null);

      if (widget.me.isMember) unawaited(_syncBestEffort());
    } catch (e) {
      _show('แนบไฟล์ไม่สำเร็จ: $e', error: true);
    }
  }

  Future<void> _sendLocation() async {
    try {
      final position = await const LocationService().getLatestLocation();

      if (position == null) {
        _show('ไม่สามารถอ่านตำแหน่งปัจจุบันได้', error: true);

        return;
      }

      await _messages.create(
        user: widget.me,

        conversationId: widget.conversation.id,

        type: 'location',

        content: 'ตำแหน่งของฉัน',

        latitude: position.latitude,

        longitude: position.longitude,

        accuracy: position.accuracyMeters,

        replyToId: _replyingTo?.id,
      );

      if (mounted) setState(() => _replyingTo = null);

      if (widget.me.isMember) unawaited(_syncBestEffort());
    } catch (e) {
      _show('ส่งตำแหน่งไม่สำเร็จ: $e', error: true);
    }
  }

  Future<void> _showAttachmentSheet() async {
    await showModalBottomSheet<void>(
      context: context,

      backgroundColor: AppColors.surface,

      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),

          child: Wrap(
            runSpacing: 8,

            children: [
              _attachmentTile(Icons.image_outlined, 'รูปภาพ', () {
                Navigator.pop(context);

                unawaited(_pickAttachment('image'));
              }),

              _attachmentTile(Icons.videocam_outlined, 'วิดีโอ', () {
                Navigator.pop(context);

                unawaited(_pickAttachment('video'));
              }),

              _attachmentTile(Icons.mic_none_rounded, 'ไฟล์เสียง', () {
                Navigator.pop(context);

                unawaited(_pickAttachment('audio'));
              }),

              _attachmentTile(Icons.attach_file_rounded, 'ไฟล์', () {
                Navigator.pop(context);

                unawaited(_pickAttachment('file'));
              }),

              _attachmentTile(Icons.location_on_outlined, 'ตำแหน่ง', () {
                Navigator.pop(context);

                unawaited(_sendLocation());
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachmentTile(IconData icon, String label, VoidCallback onTap) {
    return SizedBox(
      width: MediaQuery.sizeOf(context).width / 2 - 20,

      child: ListTile(
        leading: Icon(icon, color: AppColors.info),

        title: Text(label),

        onTap: onTap,
      ),
    );
  }

  Future<void> _openActions(LocalMessageRecord record) async {
    final mine = record.senderUserId == widget.me.id;

    final action = await showModalBottomSheet<String>(
      context: context,

      backgroundColor: AppColors.surface,

      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),

              title: const Text('ตอบกลับ'),

              onTap: () => Navigator.pop(context, 'reply'),
            ),

            ListTile(
              leading: const Icon(Icons.add_reaction_outlined),

              title: const Text('แสดงความรู้สึก'),

              onTap: () => Navigator.pop(context, 'react'),
            ),

            if (mine && record.messageType == 'text')
              ListTile(
                leading: const Icon(Icons.edit_outlined),

                title: const Text('แก้ไขข้อความ'),

                onTap: () => Navigator.pop(context, 'edit'),
              ),

            if (mine)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,

                  color: AppColors.error,
                ),

                title: const Text('ลบข้อความ'),

                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );

    switch (action) {
      case 'reply':
        setState(() => _replyingTo = record);

        break;

      case 'react':
        await _chooseReaction(record);

        break;

      case 'edit':
        await _edit(record);

        break;

      case 'delete':
        await _delete(record);

        break;
    }
  }

  Future<void> _chooseReaction(LocalMessageRecord record) async {
    final emoji = await showDialog<String>(
      context: context,

      builder: (context) => AlertDialog(
        title: const Text('แสดงความรู้สึก'),

        content: Wrap(
          spacing: 8,

          children: ['👍', '❤️', '😂', '😮', '😢', '🙏']
              .map(
                (emoji) => InkWell(
                  borderRadius: BorderRadius.circular(24),

                  onTap: () => Navigator.pop(context, emoji),

                  child: Padding(
                    padding: const EdgeInsets.all(8),

                    child: Text(emoji, style: const TextStyle(fontSize: 28)),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );

    if (emoji == null) return;

    try {
      await ChatService.instance.toggleReaction(
        conversationId: widget.conversation.id,

        messageId: record.id,

        emoji: emoji,
      );
    } catch (e) {
      _show('Reaction ไม่สำเร็จ: $e', error: true);
    }
  }

  Future<void> _edit(LocalMessageRecord record) async {
    final controller = TextEditingController(text: record.content);

    final value = await showDialog<String>(
      context: context,

      builder: (context) => AlertDialog(
        title: const Text('แก้ไขข้อความ'),

        content: TextField(
          controller: controller,

          autofocus: true,

          maxLines: 5,
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),

            child: const Text('ยกเลิก'),
          ),

          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),

            child: const Text('บันทึก'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (value == null || value.isEmpty || value == record.content) return;

    try {
      await _messages.updateText(record, value);

      if (widget.me.isMember) unawaited(_syncBestEffort());
    } catch (e) {
      _show('แก้ไขข้อความไม่สำเร็จ: $e', error: true);
    }
  }

  Future<void> _delete(LocalMessageRecord record) async {
    final yes = await showDialog<bool>(
      context: context,

      builder: (context) => AlertDialog(
        title: const Text('ลบข้อความ'),

        content: const Text('ต้องการลบข้อความนี้สำหรับทุกคนหรือไม่?'),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),

            child: const Text('ยกเลิก'),
          ),

          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),

            onPressed: () => Navigator.pop(context, true),

            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (yes != true) return;

    try {
      await _messages.delete(record);

      if (widget.me.isMember) unawaited(_syncBestEffort());
    } catch (e) {
      _show('ลบข้อความไม่สำเร็จ: $e', error: true);
    }
  }

  void _show(String text, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: error ? AppColors.error : null,

          content: Text(text),
        ),
      );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;

      _scroll.animateTo(
        _scroll.position.maxScrollExtent,

        duration: const Duration(milliseconds: 220),

        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,

        title: Row(
          children: [
            _PeerAvatar(conversation: widget.conversation),

            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    widget.conversation.displayName,

                    overflow: TextOverflow.ellipsis,
                  ),

                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: widget.me.isMember
                        ? ChatService.instance.typingStream(
                            widget.conversation.id,
                          )
                        : Stream<List<Map<String, dynamic>>>.empty(),

                    builder: (context, snapshot) {
                      final typing = (snapshot.data ?? const [])
                          .where(
                            (row) => row['user_id']?.toString() != widget.me.id,
                          )
                          .any((row) {
                            final time = DateTime.tryParse(
                              row['updated_at']?.toString() ?? '',
                            );

                            return time != null &&
                                DateTime.now()
                                        .toUtc()
                                        .difference(time.toUtc())
                                        .inSeconds <
                                    6;
                          });

                      return Text(
                        typing ? 'กำลังพิมพ์…' : 'แชทส่วนตัว',

                        style: TextStyle(
                          fontSize: 11,

                          color: typing ? AppColors.info : AppColors.muted,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),

        actions: [
          ValueListenableBuilder<SyncSnapshot>(
            valueListenable: SyncService.instance.status,

            builder: (context, value, _) => IconButton(
              tooltip: 'Sync',

              onPressed: value.isBusy ? null : SyncService.instance.retryAll,

              icon: value.isBusy
                  ? const SizedBox(
                      width: 18,

                      height: 18,

                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
            ),
          ),
        ],
      ),

      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _messageArea()),

            if (_replyingTo != null) _replyPreview(),

            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _messageArea() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: widget.me.isMember
          ? ChatService.instance.reactionStream(widget.conversation.id)
          : Stream<List<Map<String, dynamic>>>.empty(),

      builder: (context, reactionSnapshot) {
        final reactions = _groupReactions(reactionSnapshot.data ?? const []);

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: widget.me.isMember
              ? ChatService.instance.memberStateStream(widget.conversation.id)
              : Stream<List<Map<String, dynamic>>>.empty(),

          builder: (context, memberSnapshot) {
            DateTime? peerReadAt;

            for (final row in memberSnapshot.data ?? const []) {
              if (row['user_id']?.toString() == widget.me.id) continue;

              peerReadAt = DateTime.tryParse(
                row['last_read_at']?.toString() ?? '',
              )?.toLocal();
            }

            return StreamBuilder<List<LocalMessageRecord>>(
              stream: _messages.watchConversation(
                ownerLocalId: widget.me.id,

                conversationId: widget.conversation.id,
              ),

              builder: (context, snapshot) {
                final items = snapshot.data ?? const [];

                if (snapshot.hasError) {
                  return const Center(child: Text('อ่าน Local DB ไม่สำเร็จ'));
                }

                if (items.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),

                      child: Text(
                        'ยังไม่มีข้อความ\nส่งข้อความแรกเพื่อเริ่มการสนทนา',

                        textAlign: TextAlign.center,

                        style: TextStyle(color: AppColors.muted, height: 1.5),
                      ),
                    ),
                  );
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _scrollToBottom();
                });

                final byId = <String, LocalMessageRecord>{
                  for (final item in items) item.id: item,
                };

                return ListView.builder(
                  controller: _scroll,

                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),

                  itemCount: items.length,

                  itemBuilder: (context, index) {
                    final message = items[index];

                    final mine = message.senderUserId == widget.me.id;

                    return _MessageBubble(
                      message: message,

                      replyMessage: message.replyToId == null
                          ? null
                          : byId[message.replyToId!],

                      mine: mine,

                      peerReadAt: peerReadAt,

                      reactions: reactions[message.id] ?? const {},

                      onLongPress: () => _openActions(message),

                      onRetry: message.syncState == 'error'
                          ? () async {
                              await _messages.retry(message.id);

                              await SyncService.instance.retryAll();
                            }
                          : null,

                      onOpenMedia: () => _openMedia(message),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Map<String, Map<String, int>> _groupReactions(
    List<Map<String, dynamic>> rows,
  ) {
    final result = <String, Map<String, int>>{};

    for (final row in rows) {
      final id = row['message_id']?.toString();

      final emoji = row['emoji']?.toString();

      if (id == null || emoji == null) continue;

      final map = result.putIfAbsent(id, () => <String, int>{});

      map[emoji] = (map[emoji] ?? 0) + 1;
    }

    return result;
  }

  Widget _replyPreview() {
    final reply = _replyingTo!;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),

      padding: const EdgeInsets.all(10),

      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,

        borderRadius: BorderRadius.circular(12),

        border: Border.all(color: AppColors.border),
      ),

      child: Row(
        children: [
          const Icon(Icons.reply_rounded, color: AppColors.info),

          const SizedBox(width: 8),

          Expanded(
            child: Text(
              reply.content.isEmpty
                  ? _attachmentLabel(reply.messageType, reply.mediaName ?? '')
                  : reply.content,

              maxLines: 1,

              overflow: TextOverflow.ellipsis,
            ),
          ),

          IconButton(
            visualDensity: VisualDensity.compact,

            onPressed: () => setState(() => _replyingTo = null),

            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,

        children: [
          IconButton(
            tooltip: 'แนบไฟล์',

            onPressed: _showAttachmentSheet,

            icon: const Icon(Icons.add_circle_outline_rounded),
          ),

          Expanded(
            child: TextField(
              controller: _text,

              onChanged: _typingChanged,

              minLines: 1,

              maxLines: 5,

              textInputAction: TextInputAction.newline,

              decoration: const InputDecoration(
                hintText: 'พิมพ์ข้อความ…',

                contentPadding: EdgeInsets.symmetric(
                  horizontal: 14,

                  vertical: 12,
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          IconButton.filled(
            onPressed: _sending ? null : _sendText,

            icon: _sending
                ? const SizedBox(
                    width: 18,

                    height: 18,

                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _openMedia(LocalMessageRecord message) async {
    if (message.messageType == 'location' &&
        message.latitude != null &&
        message.longitude != null) {
      final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${message.latitude},${message.longitude}',
      );

      await launchUrl(uri, mode: LaunchMode.externalApplication);

      return;
    }

    final url = await ChatService.instance.signedMediaUrl(message.mediaPath);

    if (url == null) {
      _show('ไฟล์ยังรออัปโหลดหรือไม่สามารถเปิดได้', error: true);

      return;
    }

    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  String _mimeFor(String name, String kind) {
    final parts = name.split('.');

    final ext = parts.length > 1 ? parts.last.toLowerCase() : '';

    const known = <String, String>{
      // Images
      'jpg': 'image/jpeg',

      'jpeg': 'image/jpeg',

      'png': 'image/png',

      'gif': 'image/gif',

      'webp': 'image/webp',

      // Video
      'mp4': 'video/mp4',

      'mov': 'video/quicktime',

      'm4v': 'video/x-m4v',

      'avi': 'video/x-msvideo',

      // Audio
      'mp3': 'audio/mpeg',

      'm4a': 'audio/mp4',

      'wav': 'audio/wav',

      'aac': 'audio/aac',

      // Documents
      'pdf': 'application/pdf',

      'txt': 'text/plain',

      'csv': 'text/csv',

      // Microsoft Word
      'doc': 'application/msword',

      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',

      // Microsoft Excel
      'xls': 'application/vnd.ms-excel',

      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',

      // Microsoft PowerPoint
      'ppt': 'application/vnd.ms-powerpoint',

      'pptx':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',

      // Microsoft Access
      'mdb': 'application/x-msaccess',

      'accdb': 'application/x-msaccess',

      // Archives
      'zip': 'application/zip',

      'rar': 'application/vnd.rar',

      '7z': 'application/x-7z-compressed',
    };

    return known[ext] ??
        switch (kind) {
          'image' => 'image/jpeg',

          'video' => 'video/mp4',

          'audio' => 'audio/mpeg',

          _ => 'application/octet-stream',
        };
  }

  String _attachmentLabel(String kind, String name) => switch (kind) {
    'image' => '📷 รูปภาพ${name.isEmpty ? '' : ' • $name'}',

    'video' => '🎬 วิดีโอ${name.isEmpty ? '' : ' • $name'}',

    'audio' => '🎵 ไฟล์เสียง${name.isEmpty ? '' : ' • $name'}',

    'file' => '📎 ไฟล์${name.isEmpty ? '' : ' • $name'}',

    'location' => '📍 ตำแหน่ง',

    _ => name,
  };
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,

    required this.replyMessage,

    required this.mine,

    required this.peerReadAt,

    required this.reactions,

    required this.onLongPress,

    required this.onOpenMedia,

    this.onRetry,
  });

  final LocalMessageRecord message;

  final LocalMessageRecord? replyMessage;

  final bool mine;

  final DateTime? peerReadAt;

  final Map<String, int> reactions;

  final VoidCallback onLongPress;

  final VoidCallback onOpenMedia;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final read =
        mine &&
        message.syncState == 'synced' &&
        peerReadAt != null &&
        !peerReadAt!.isBefore(message.createdAt);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,

      child: GestureDetector(
        onLongPress: onLongPress,

        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * .78,
          ),

          margin: const EdgeInsets.only(bottom: 8),

          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),

          decoration: BoxDecoration(
            color: mine
                ? AppColors.info.withValues(alpha: .17)
                : AppColors.surfaceSoft,

            borderRadius: BorderRadius.circular(16),

            border: Border.all(
              color: mine
                  ? AppColors.info.withValues(alpha: .32)
                  : AppColors.border,
            ),
          ),

          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,

            children: [
              if (!mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),

                  child: Text(
                    message.senderName,

                    style: const TextStyle(
                      color: AppColors.info,

                      fontSize: 11,

                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),

              if (replyMessage != null) ...[
                Container(
                  width: double.infinity,

                  margin: const EdgeInsets.only(bottom: 6),

                  padding: const EdgeInsets.all(7),

                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: .35),

                    borderRadius: BorderRadius.circular(8),

                    border: const Border(
                      left: BorderSide(color: AppColors.info, width: 3),
                    ),
                  ),

                  child: Text(
                    replyMessage!.content.isEmpty
                        ? 'ข้อความแนบไฟล์'
                        : replyMessage!.content,

                    maxLines: 2,

                    overflow: TextOverflow.ellipsis,

                    style: const TextStyle(
                      fontSize: 11,

                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],

              if (message.messageType == 'text')
                Align(
                  alignment: Alignment.centerLeft,

                  child: Text(message.content),
                )
              else if (message.messageType == 'image')
                _imageContent()
              else if (message.messageType == 'video')
                _InlineVideoContent(
                  message: message,

                  onOpenExternal: onOpenMedia,
                )
              else
                InkWell(
                  onTap: onOpenMedia,

                  borderRadius: BorderRadius.circular(10),

                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),

                    child: Row(
                      mainAxisSize: MainAxisSize.min,

                      children: [
                        Icon(
                          _typeIcon(message.messageType),

                          color: AppColors.info,
                        ),

                        const SizedBox(width: 8),

                        Flexible(child: Text(message.content)),
                      ],
                    ),
                  ),
                ),

              if (reactions.isNotEmpty) ...[
                const SizedBox(height: 5),

                Wrap(
                  spacing: 4,

                  children: reactions.entries
                      .map(
                        (entry) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,

                            vertical: 2,
                          ),

                          decoration: BoxDecoration(
                            color: AppColors.background.withValues(alpha: .45),

                            borderRadius: BorderRadius.circular(12),
                          ),

                          child: Text('${entry.key} ${entry.value}'),
                        ),
                      )
                      .toList(),
                ),
              ],

              const SizedBox(height: 4),

              Row(
                mainAxisSize: MainAxisSize.min,

                children: [
                  if (message.editedAt != null)
                    const Text(
                      'แก้ไขแล้ว • ',

                      style: TextStyle(fontSize: 9, color: AppColors.muted),
                    ),

                  Text(
                    _hhmm(message.createdAt),

                    style: const TextStyle(fontSize: 9, color: AppColors.muted),
                  ),

                  if (mine) ...[
                    const SizedBox(width: 5),

                    if (onRetry != null)
                      InkWell(
                        onTap: onRetry,

                        child: const Icon(
                          Icons.refresh_rounded,

                          size: 14,

                          color: AppColors.error,
                        ),
                      )
                    else
                      Text(
                        read
                            ? 'อ่านแล้ว'
                            : message.syncState == 'synced'
                            ? 'ส่งแล้ว'
                            : message.syncState,

                        style: TextStyle(
                          fontSize: 9,

                          color: read ? AppColors.info : AppColors.muted,

                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageContent() {
    final local = message.mediaBytes;

    if (local != null && local.isNotEmpty) {
      return InkWell(
        onTap: onOpenMedia,

        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),

          child: Image.memory(
            Uint8List.fromList(local),

            width: 220,

            height: 170,

            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return FutureBuilder<String?>(
      future: ChatService.instance.signedMediaUrl(message.mediaPath),

      builder: (context, snapshot) {
        final url = snapshot.data;

        if (url == null) {
          return InkWell(
            onTap: onOpenMedia,

            child: const SizedBox(
              width: 180,

              height: 110,

              child: Center(child: Icon(Icons.image_outlined, size: 42)),
            ),
          );
        }

        return InkWell(
          onTap: onOpenMedia,

          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),

            child: Image.network(
              url,

              width: 220,

              height: 170,

              fit: BoxFit.cover,

              errorBuilder: (context, error, stackTrace) => const SizedBox(
                width: 180,

                height: 110,

                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
        );
      },
    );
  }

  static IconData _typeIcon(String type) => switch (type) {
    'image' => Icons.image_outlined,

    'video' => Icons.videocam_outlined,

    'audio' => Icons.audiotrack_rounded,

    'location' => Icons.location_on_outlined,

    _ => Icons.insert_drive_file_outlined,
  };

  static String _hhmm(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');

    final m = value.minute.toString().padLeft(2, '0');

    return '$h:$m';
  }
}

class _InlineVideoContent extends StatefulWidget {
  const _InlineVideoContent({
    required this.message,

    required this.onOpenExternal,
  });

  final LocalMessageRecord message;

  final VoidCallback onOpenExternal;

  @override
  State<_InlineVideoContent> createState() => _InlineVideoContentState();
}

class _InlineVideoContentState extends State<_InlineVideoContent> {
  VideoPlayerController? _controller;

  String? _url;

  Object? _error;

  bool _loading = true;

  @override
  void initState() {
    super.initState();

    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _InlineVideoContent oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.message.mediaPath != widget.message.mediaPath) {
      unawaited(_reload());
    }
  }

  Future<void> _reload() async {
    final previous = _controller;

    _controller = null;

    await previous?.dispose();

    if (!mounted) return;

    setState(() {
      _url = null;

      _error = null;

      _loading = true;
    });

    await _load();
  }

  Future<void> _load() async {
    final path = widget.message.mediaPath;

    if (path == null || path.isEmpty) {
      if (!mounted) return;

      setState(() => _loading = false);

      return;
    }

    try {
      final url = await ChatService.instance.signedMediaUrl(path);

      if (!mounted) return;

      if (url == null || url.isEmpty) {
        setState(() => _loading = false);

        return;
      }

      final controller = VideoPlayerController.networkUrl(Uri.parse(url));

      await controller.initialize();

      await controller.setLooping(false);

      if (!mounted) {
        await controller.dispose();

        return;
      }

      setState(() {
        _url = url;

        _controller = controller;

        _loading = false;

        _error = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error;

        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();

    super.dispose();
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;

    if (controller == null) return;

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  void _openFullscreen() {
    final url = _url;

    if (url == null || url.isEmpty) return;

    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => _FullScreenVideo(url: url)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 240,

        height: 135,

        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return InkWell(
        onTap: widget.onOpenExternal,

        borderRadius: BorderRadius.circular(10),

        child: SizedBox(
          width: 240,

          height: 120,

          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,

            children: [
              const Icon(
                Icons.videocam_outlined,

                size: 38,

                color: AppColors.info,
              ),

              const SizedBox(height: 6),

              Text(
                _error == null
                    ? 'Video is waiting for upload'
                    : 'Inline video playback is unavailable',

                textAlign: TextAlign.center,

                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),

              const SizedBox(height: 4),

              const Text(
                'Tap to open externally',

                style: TextStyle(color: AppColors.info, fontSize: 10),
              ),
            ],
          ),
        ),
      );
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,

      builder: (context, value, _) {
        final ratio = value.aspectRatio > 0 ? value.aspectRatio : 16 / 9;

        return SizedBox(
          width: 250,

          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),

            child: ColoredBox(
              color: Colors.black,

              child: Column(
                mainAxisSize: MainAxisSize.min,

                children: [
                  AspectRatio(
                    aspectRatio: ratio,

                    child: Stack(
                      fit: StackFit.expand,

                      children: [
                        VideoPlayer(controller),

                        Material(
                          color: Colors.transparent,

                          child: InkWell(
                            onTap: _togglePlayback,

                            child: Center(
                              child: AnimatedOpacity(
                                opacity: value.isPlaying ? 0 : 1,

                                duration: const Duration(milliseconds: 160),

                                child: Container(
                                  width: 54,

                                  height: 54,

                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: .58),

                                    shape: BoxShape.circle,
                                  ),

                                  child: const Icon(
                                    Icons.play_arrow_rounded,

                                    color: Colors.white,

                                    size: 38,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          top: 4,

                          right: 4,

                          child: IconButton.filledTonal(
                            tooltip: 'Full screen',

                            onPressed: _openFullscreen,

                            icon: const Icon(Icons.fullscreen_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),

                  VideoProgressIndicator(
                    controller,

                    allowScrubbing: true,

                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,

                      vertical: 8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FullScreenVideo extends StatefulWidget {
  const _FullScreenVideo({required this.url});

  final String url;

  @override
  State<_FullScreenVideo> createState() => _FullScreenVideoState();
}

class _FullScreenVideoState extends State<_FullScreenVideo> {
  late final VideoPlayerController _controller;

  bool _ready = false;

  Object? _error;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));

    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();

      await _controller.setLooping(false);

      await _controller.play();

      if (!mounted) return;

      setState(() => _ready = true);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error;

        _ready = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  Future<void> _toggle() async {
    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      await _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        backgroundColor: Colors.black,

        foregroundColor: Colors.white,

        title: const Text('Video'),
      ),

      body: Center(
        child: _error != null
            ? const Text(
                'Unable to play this video.',

                style: TextStyle(color: Colors.white),
              )
            : !_ready
            ? const CircularProgressIndicator()
            : ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _controller,

                builder: (context, value, _) {
                  final ratio = value.aspectRatio > 0
                      ? value.aspectRatio
                      : 16 / 9;

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,

                    children: [
                      Flexible(
                        child: GestureDetector(
                          onTap: _toggle,

                          child: AspectRatio(
                            aspectRatio: ratio,

                            child: VideoPlayer(_controller),
                          ),
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),

                        child: VideoProgressIndicator(
                          _controller,

                          allowScrubbing: true,
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _PeerAvatar extends StatelessWidget {
  const _PeerAvatar({required this.conversation});

  final LocalChatConversation conversation;

  @override
  Widget build(BuildContext context) {
    final parts = conversation.displayName.trim().split(RegExp(r'\s+'));

    final initial = parts.isEmpty || parts.first.isEmpty
        ? '?'
        : parts.first.characters.first.toUpperCase();

    return CircleAvatar(
      radius: 18,

      backgroundColor: AppColors.surfaceSoft,

      child: Text(initial, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}
