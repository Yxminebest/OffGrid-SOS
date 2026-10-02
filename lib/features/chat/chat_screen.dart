import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models/local_message_record.dart';
import '../../data/repositories/message_repository.dart';
import '../../models/user.dart';
import '../../services/sync_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.me});

  final AppUser me;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _message = TextEditingController();

  final MessageRepository _repository = MessageRepository();

  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text.trim();

    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);

    try {
      await _repository.create(user: widget.me, content: text);

      if (widget.me.isMember) {
        await SyncService.instance.syncNow();
      }

      _message.clear();

      if (!mounted) return;

      _show(
        widget.me.isMember
            ? 'บันทึกข้อความลง Local DB แล้ว'
            : 'Guest: ข้อความถูกเก็บไว้ใน Local DB',
      );
    } catch (e) {
      if (!mounted) return;

      _show('บันทึกข้อความไม่สำเร็จ: $e', error: true);
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _openActions(LocalMessageRecord record) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('แก้ไขข้อความ'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
              title: const Text('ลบข้อความ'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (action == 'edit') {
      await _edit(record);
    } else if (action == 'delete') {
      await _delete(record);
    }
  }

  Future<void> _edit(LocalMessageRecord record) async {
    final controller = TextEditingController(text: record.content);

    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('แก้ไขข้อความ'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
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

    if (text == null || text.isEmpty) return;

    try {
      await _repository.updateText(record, text);

      if (widget.me.isMember) {
        await SyncService.instance.syncNow();
      }
    } catch (e) {
      if (!mounted) return;

      _show('แก้ไขข้อความไม่สำเร็จ: $e', error: true);
    }
  }

  Future<void> _delete(LocalMessageRecord record) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบข้อความ'),
        content: const Text(
          'ข้อความจะหายจาก Local DB และจะลบจาก Cloud เมื่อซิงก์สำเร็จ',
        ),
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

    if (confirm != true) return;

    try {
      await _repository.delete(record);

      if (widget.me.isMember) {
        await SyncService.instance.syncNow();
      }
    } catch (e) {
      if (!mounted) return;

      _show('ลบข้อความไม่สำเร็จ: $e', error: true);
    }
  }

  void _show(String text, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: error ? AppColors.error : null,
          content: Text(text),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline_rounded),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'แชท',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Week 3: Local DB → Supabase Sync',
                        style: TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                ValueListenableBuilder<SyncSnapshot>(
                  valueListenable: SyncService.instance.status,
                  builder: (context, value, _) {
                    return IconButton(
                      tooltip: 'Retry Sync (${value.pendingCount})',
                      onPressed: value.isBusy
                          ? null
                          : SyncService.instance.retryAll,
                      icon: value.isBusy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded),
                    );
                  },
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.info.withValues(alpha: .22)),
            ),
            child: Text(
              widget.me.isMember
                  ? 'ข้อความจะปรากฏจาก Local DB ทันที แล้วจึง Sync Cloud'
                  : 'Guest mode: ข้อความถูกเก็บใน Local DB เท่านั้น',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<LocalMessageRecord>>(
              stream: _repository.watchForUser(widget.me.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('อ่าน Local DB ไม่สำเร็จ'));
                }

                final messages = snapshot.data ?? const [];

                if (messages.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                        'ยังไม่มีข้อความ\n'
                        'ลองส่งข้อความ แล้ว Refresh หน้าเว็บหรือเปิดแอปใหม่ '
                        'ข้อความต้องยังอยู่ เพราะอ่านจาก Local DB',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, height: 1.5),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final record = messages[index];

                    return Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onLongPress: () => _openActions(record),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 300),
                          margin: const EdgeInsets.only(bottom: 9),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.info.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.info.withValues(alpha: .30),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(record.content),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (record.syncState == 'error')
                                    InkWell(
                                      onTap: () async {
                                        await _repository.retry(record.id);
                                        await SyncService.instance.retryAll();
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.only(right: 6),
                                        child: Icon(
                                          Icons.refresh_rounded,
                                          size: 15,
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ),
                                  Text(
                                    record.syncState,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: record.syncState == 'error'
                                          ? AppColors.error
                                          : AppColors.muted,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _message,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'พิมพ์ข้อความ...',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
