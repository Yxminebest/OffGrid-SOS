import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models/local_chat_conversation.dart';
import '../../models/chat_user.dart';
import '../../models/user.dart';
import '../../services/chat_service.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key, required this.me});

  final AppUser me;

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<ChatUser> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_runSearch(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_runSearch(value));
    });
  }

  Future<void> _runSearch(String value) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final users = await ChatService.instance.searchUsers(value);
      if (!mounted) return;
      setState(() => _results = users);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'ค้นหาผู้ใช้ไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(ChatUser peer) async {
    try {
      final conversation = await ChatService.instance.getOrCreateDirect(
        me: widget.me,
        peer: peer,
      );
      if (!mounted) return;
      Navigator.pop<LocalChatConversation>(context, conversation);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เปิดห้องสนทนาไม่สำเร็จ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เริ่มแชทใหม่')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                controller: _search,
                onChanged: _onChanged,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'ค้นหาจากชื่อจริงหรือนามสกุล',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            Expanded(
              child: _results.isEmpty && !_loading
                  ? const Center(
                      child: Text(
                        'ไม่พบผู้ใช้',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: _results.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final user = _results[index];
                        final initials = _initials(user.fullName);
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: AppColors.surfaceSoft,
                            child: Text(
                              initials,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          title: Text(
                            user.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            switch (user.role) {
                              'admin' => 'ผู้ดูแลระบบ',
                              'rescuer' => 'หน่วยกู้ภัยที่ยืนยันแล้ว',
                              _ => 'ผู้ใช้',
                            },
                            style: const TextStyle(color: AppColors.muted),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _open(user),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }
}
