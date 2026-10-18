import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models/local_sos_record.dart';
import '../../data/repositories/sos_repository.dart';
import '../../widgets/appearance_picker.dart';
import '../../widgets/app_card.dart';
import '../../widgets/brand_mark.dart';
import '../../data/models/local_chat_conversation.dart';
import '../../data/repositories/nearby_chat_repository.dart';
import '../../models/user.dart';
import '../../services/chat_service.dart';
import '../../services/nearby_mesh_service.dart';
import '../../services/chat_camera_service.dart';
import '../../services/sync_service.dart';
import '../../services/app_notifications.dart';
import '../../services/cloud_inbox_service.dart';
import '../../services/network_service.dart';
import '../auth/rescue_verification_screen.dart';
import '../chat/chat_screen.dart';
import '../chat/conversation_screen.dart';
import '../nearby/nearby_screen.dart';
import '../profile/profile_screen.dart';
import '../rescue/rescue_screen.dart';
import '../sos/sos_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.me, required this.onLogout});

  final AppUser me;
  final Future<void> Function() onLogout;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _unreadTotal = 0;
  int _nearbyUnread = 0;
  int get _combinedUnread => _unreadTotal + _nearbyUnread;
  StreamSubscription<List<NearbyThread>>? _nearbyInboxSubscription;
  bool _inboxPrimed = false;
  Map<String, int> _unreadByConversation = <String, int>{};
  StreamSubscription<List<LocalChatConversation>>? _inboxSubscription;

  @override
  void initState() {
    super.initState();
    unawaited(_startServices());
    _nearbyInboxSubscription = NearbyMeshService.instance.chats
        .watchThreads(widget.me.id)
        .listen((threads) {
          if (mounted) {
            setState(
              () => _nearbyUnread = threads.fold(
                0,
                (sum, thread) => sum + thread.unread,
              ),
            );
          }
        }, onError: (_) {});

    if (widget.me.isMember) {
      _inboxSubscription = ChatService.instance
          .watchInbox(widget.me.id)
          .listen(_handleInbox, onError: (_) {});
    }
  }

  Future<void> _startServices() async {
    try {
      await NearbyMeshService.instance.initializeForUser(widget.me);
      NetworkService.instance.start();
      await AppNotifications.instance.startBackground();
      await CloudInboxService.instance.start(widget.me);
      if (!mounted) return;
      await SyncService.instance.start();
      try {
        final recovered = await ChatCameraService.instance.recoverFor(
          widget.me,
        );
        if (recovered && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('กู้คืนรูปจากกล้องและบันทึกเข้าห้องแชทแล้ว'),
            ),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'มีรูปจากกล้องค้างอยู่ กรุณาตรวจพื้นที่ว่างแล้วเปิดแอปใหม่',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('เริ่มบริการไม่สำเร็จ: $e')));
    }
  }

  @override
  void dispose() {
    _inboxSubscription?.cancel();
    _nearbyInboxSubscription?.cancel();
    unawaited(SyncService.instance.stop());
    super.dispose();
  }

  void _handleInbox(List<LocalChatConversation> conversations) {
    final nextUnread = conversations.fold<int>(
      0,
      (sum, item) => sum + item.unreadCount,
    );

    LocalChatConversation? newestUnread;
    if (_inboxPrimed) {
      for (final conversation in conversations) {
        final before = _unreadByConversation[conversation.id] ?? 0;
        if (conversation.unreadCount <= before) continue;

        if (newestUnread == null) {
          newestUnread = conversation;
          continue;
        }

        final currentTime =
            conversation.lastMessageAt ?? conversation.updatedAt;
        final newestTime = newestUnread.lastMessageAt ?? newestUnread.updatedAt;
        if (currentTime.isAfter(newestTime)) {
          newestUnread = conversation;
        }
      }
    }

    _unreadByConversation = <String, int>{
      for (final conversation in conversations)
        conversation.id: conversation.unreadCount,
    };
    _inboxPrimed = true;

    if (mounted && nextUnread != _unreadTotal) {
      setState(() => _unreadTotal = nextUnread);
    } else {
      _unreadTotal = nextUnread;
    }

    if (newestUnread != null &&
        _index != 2 &&
        !AppNotifications.instance.supported) {
      final conversation = newestUnread;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _index == 2) return;
        final preview = conversation.lastMessage?.trim();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
              content: Text(
                preview == null || preview.isEmpty
                    ? 'ข้อความใหม่จาก ${conversation.displayName}'
                    : '${conversation.displayName}: $preview',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              action: SnackBarAction(
                label: 'เปิดแชท',
                onPressed: () {
                  if (!mounted) return;

                  setState(() => _index = 2);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ConversationScreen(
                        me: widget.me,
                        conversation: conversation,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
      });
    }
  }

  Widget _chatNavIcon(IconData icon) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (_combinedUnread > 0)
          Positioned(
            right: -10,
            top: -8,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                _combinedUnread > 99 ? '99+' : '$_combinedUnread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openSos() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => SosScreen(me: widget.me)));
  }

  Future<void> _openRescue() async {
    if (!widget.me.isMember) {
      _notice('ต้องสมัครสมาชิกก่อนใช้งาน RESCUE MODE');
      return;
    }

    if (!widget.me.isVerifiedRescuer) {
      final openVerification = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ยังไม่มีสิทธิ์ RESCUE MODE'),
          content: const Text(
            'RESCUE MODE ใช้ได้เฉพาะบัญชีหน่วยกู้ภัยที่ผ่านการตรวจสอบจาก Admin เท่านั้น',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ปิด'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ยื่นคำขอยืนยัน'),
            ),
          ],
        ),
      );

      if (!mounted || openVerification != true) return;

      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RescueVerificationScreen()),
      );
      return;
    }

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => RescueScreen(me: widget.me)));
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeDashboard(
        me: widget.me,
        onSos: _openSos,
        onRescue: _openRescue,
        onNearby: () => setState(() => _index = 1),
        onChat: () => setState(() => _index = 2),
        unreadCount: _combinedUnread,
      ),
      NearbyScreen(me: widget.me),
      ChatScreen(me: widget.me),
      ProfileScreen(me: widget.me, onLogout: widget.onLogout),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() => _index = value);
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'หน้าหลัก',
          ),
          const NavigationDestination(
            icon: Icon(Icons.radar_outlined),
            selectedIcon: Icon(Icons.radar_rounded),
            label: 'ใกล้เคียง',
          ),
          NavigationDestination(
            icon: _chatNavIcon(Icons.chat_bubble_outline_rounded),
            selectedIcon: _chatNavIcon(Icons.chat_bubble_rounded),
            label: 'แชท',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'โปรไฟล์',
          ),
        ],
      ),
    );
  }
}

class HomeDashboard extends StatelessWidget {
  const HomeDashboard({
    super.key,
    required this.me,
    required this.onSos,
    required this.onRescue,
    required this.onNearby,
    required this.onChat,
    required this.unreadCount,
    this.sosRecords,
  });
  final AppUser me;
  final VoidCallback onSos, onRescue, onNearby, onChat;
  final int unreadCount;
  final Stream<List<LocalSosRecord>>? sosRecords;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
          children: [
            const Row(
              children: [
                Expanded(child: BrandLockup()),
                ThemeModeButton(),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              'สวัสดี, ${me.firstName}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'ดูแลตัวเอง และอยู่ใกล้คนที่สำคัญ',
              style: TextStyle(color: context.colors.muted, fontSize: 14),
            ),
            const SizedBox(height: 22),
            StreamBuilder<List<LocalSosRecord>>(
              stream: sosRecords ?? SosRepository().watchForUser(me.id),
              builder: (context, snapshot) => _SosHero(
                active: (snapshot.data ?? []).any((r) => r.isActive),
                onTap: onSos,
              ),
            ),
            const SizedBox(height: 16),
            _SyncOverview(isMember: me.isMember),
            const SizedBox(height: 26),
            Text(
              'เชื่อมต่อและช่วยเหลือ',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListenableBuilder(
                    listenable: NearbyMeshService.instance,
                    builder: (context, _) {
                      final mesh = NearbyMeshService.instance;
                      return _ActionRow(
                        icon: Icons.radar_rounded,
                        title: 'คนใกล้เคียง',
                        detail: mesh.connected.isNotEmpty
                            ? 'เชื่อมต่อ ${mesh.connected.length} เครื่อง'
                            : mesh.running
                            ? 'กำลังค้นหาอุปกรณ์'
                            : 'เชื่อมต่อผ่าน Bluetooth และ Wi-Fi',
                        color: context.colors.info,
                        onTap: onNearby,
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 74, endIndent: 20),
                  _ActionRow(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'ข้อความของคุณ',
                    detail: unreadCount > 0
                        ? 'มี $unreadCount ข้อความที่ยังไม่ได้อ่าน'
                        : me.isMember
                        ? 'ติดตามและพูดคุยกับคนที่คุณติดต่อ'
                        : 'เข้าสู่ระบบเพื่อเริ่มแชทส่วนตัว',
                    color: context.colors.info,
                    onTap: onChat,
                    count: unreadCount,
                  ),
                  const Divider(height: 1, indent: 74, endIndent: 20),
                  _ActionRow(
                    icon: Icons.health_and_safety_outlined,
                    title: 'หน่วยกู้ภัย',
                    detail: me.isVerifiedRescuer
                        ? 'เปิดโหมดปฏิบัติหน้าที่'
                        : 'สำหรับหน่วยกู้ภัยที่ยืนยันตัวตนแล้ว',
                    color: context.colors.rescue,
                    onTap: onRescue,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.explore_outlined,
                  color: context.colors.info,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'ก่อนออกเดินทาง เปิดตำแหน่งและจับคู่ Nearby กับคนที่ไปด้วยกัน',
                    style: TextStyle(
                      color: context.colors.muted,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _SosHero extends StatelessWidget {
  const _SosHero({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: active ? 'ดู SOS ที่กำลังทำงาน' : 'เปิดหน้าขอความช่วยเหลือฉุกเฉิน',
    child: Material(
      color: const Color(0xFF352D19),
      borderRadius: BorderRadius.circular(26),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          active
                              ? 'SOS กำลังทำงาน'
                              : 'เมื่อคุณต้องการความช่วยเหลือ',
                          style: const TextStyle(
                            color: Color(0xFFF3CF70),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          active ? 'ติดตาม SOS ของคุณ' : 'ทุกก้าว อุ่นใจได้',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .09),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.sos_rounded,
                      color: Color(0xFFF3CF70),
                      size: 28,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                active
                    ? 'บันทึกในเครื่องแล้ว เปิดดูสถานะการส่งได้ที่นี่'
                    : 'บันทึกเหตุฉุกเฉินพร้อมพิกัด แม้ไม่มีอินเทอร์เน็ต',
                style: const TextStyle(
                  color: Color(0xFFE6D9B3),
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppColors.sos,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.sos_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        active ? 'ดูรายละเอียด SOS' : 'เปิดหน้า SOS',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SyncOverview extends StatelessWidget {
  const _SyncOverview({required this.isMember});
  final bool isMember;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SyncSnapshot>(
    valueListenable: SyncService.instance.status,
    builder: (context, sync, _) {
      final title = !isMember
          ? 'บันทึกในเครื่องได้ ไม่ต้องสมัครสมาชิก'
          : switch (sync.activity) {
              SyncActivity.offline => 'ออฟไลน์ · ยังบันทึก SOS ในเครื่องได้',
              SyncActivity.syncing => 'กำลังส่งข้อมูล',
              SyncActivity.error => 'ยังส่งข้อมูลบางรายการไม่ได้',
              SyncActivity.success => 'ซิงก์ข้อมูลแล้ว',
              _ =>
                sync.pendingCount > 0
                    ? 'มี ${sync.pendingCount} รายการรอส่ง'
                    : 'พร้อมบันทึกข้อมูลในเครื่อง',
            };
      return Row(
        children: [
          Icon(
            sync.activity == SyncActivity.offline
                ? Icons.cloud_off_outlined
                : Icons.shield_outlined,
            color: context.colors.info,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: context.colors.muted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
          if (isMember && sync.pendingCount > 0)
            IconButton(
              tooltip: 'ลองส่งข้อมูลอีกครั้ง',
              onPressed: sync.isBusy ? null : SyncService.instance.retryAll,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      );
    },
  );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
    required this.onTap,
    this.count = 0,
  });
  final IconData icon;
  final String title, detail;
  final Color color;
  final VoidCallback onTap;
  final int count;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: TextStyle(
                    color: context.colors.muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (count > 0)
            Badge(label: Text('$count'))
          else
            Icon(
              Icons.chevron_right_rounded,
              color: context.colors.muted,
              size: 20,
            ),
        ],
      ),
    ),
  );
}
