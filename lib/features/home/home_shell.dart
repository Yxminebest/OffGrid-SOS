import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models/local_sos_record.dart';
import '../../data/repositories/sos_repository.dart';
import '../../widgets/app_card.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/emergency_home_panel.dart';
import '../../data/models/local_chat_conversation.dart';
import '../../models/user.dart';
import '../../services/chat_service.dart';
import '../../services/location_service.dart';
import '../../widgets/nearby_people_panel.dart';
import '../../services/unified_chat_service.dart';
import '../../services/home_return_policy.dart';
import '../../services/nearby_mesh_service.dart';
import '../../services/chat_camera_service.dart';
import '../../services/sync_service.dart';
import '../../services/app_notifications.dart';
import '../../services/rescue_status_service.dart';
import '../../services/cloud_inbox_service.dart';
import '../../services/offline_media_service.dart';
import '../../services/network_service.dart';
import '../auth/rescue_verification_screen.dart';
import '../chat/chat_screen.dart';
import '../chat/unified_conversation_screen.dart';
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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final _returnPolicy = HomeReturnPolicy();
  late AppUser _me;
  String? _lastRescueNotice;
  int _index = 0;
  late final _sosRecords = SosRepository().watchForUser(widget.me.id);
  final _visitedTabs = <int>{0};
  int _nearbyUnread = 0;
  int get _combinedUnread => _nearbyUnread;
  StreamSubscription<List<ChatInboxEntry>>? _nearbyInboxSubscription;
  bool _inboxPrimed = false;
  Map<String, int> _unreadByConversation = <String, int>{};
  StreamSubscription<List<LocalChatConversation>>? _inboxSubscription;
  bool _notificationReady = false, _checkingNotification = false;
  bool _notificationAgain = false, _returningHome = false;
  Map<String, String>? _pendingNotificationTap;

  @override
  void initState() {
    super.initState();
    _me = widget.me;
    unawaited(const LocationService().prepare());
    WidgetsBinding.instance.addObserver(this);
    AppNotifications.instance.listenForTaps();
    AppNotifications.instance.taps.addListener(_scheduleNotificationTap);
    RescueStatusService.instance.addListener(_onRescueStatus);
    unawaited(_startServices());
    _nearbyInboxSubscription = UnifiedChatService.instance
        .watchInbox(_me.id)
        .listen((threads) {
          final unread = threads.fold<int>(
            0,
            (sum, thread) => sum + thread.unread,
          );
          if (mounted && unread != _nearbyUnread) {
            setState(() => _nearbyUnread = unread);
          }
        }, onError: (_) {});

    if (_me.isMember && !AppNotifications.instance.supported) {
      _inboxSubscription = ChatService.instance
          .watchInbox(_me.id)
          .listen(_handleInbox, onError: (_) {});
    }
  }

  Future<void> _startServices() async {
    try {
      await NearbyMeshService.instance.initializeForUser(_me);
      if (!mounted) return;
      UnifiedChatService.instance.start(_me);
      _notificationReady = true;
      _scheduleNotificationTap();
      // Radio and local camera recovery must never wait for cloud services.
      unawaited(
        NearbyMeshService.instance
            .resumePreferred(_me, startIfUnset: true)
            .then((_) => const LocationService().prepare())
            .catchError((_) {}),
      );
      NetworkService.instance.start();
      unawaited(AppNotifications.instance.startBackground().catchError((_) {}));
      if (_me.isMember) unawaited(_startCloudServices());
      try {
        final recovered = await ChatCameraService.instance.recoverFor(_me);
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

  Future<void> _startCloudServices() async {
    OfflineMediaService.instance.start(_me);
    unawaited(NearbyMeshService.instance.refreshAttestation());
    try {
      await CloudInboxService.instance.start(_me);
    } catch (_) {}
    if (!mounted) return;
    try {
      await SyncService.instance.start();
    } catch (_) {}
    if (!mounted) return;
    unawaited(RescueStatusService.instance.start(_me));
  }

  void _onRescueStatus() {
    if (!mounted) return;
    final status = RescueStatusService.instance;
    final updated = status.member;
    if (updated == null || updated.id != _me.id) return;
    if (updated.role != _me.role) {
      setState(() => _me = updated);
      unawaited(NearbyMeshService.instance.initializeForUser(updated));
      unawaited(NearbyMeshService.instance.refreshAttestation(force: true));
    }
    final notice = status.notice;
    if (notice != null && notice.id != _lastRescueNotice) {
      _lastRescueNotice = notice.id;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(notice.title),
          action: SnackBarAction(
            label: 'ดูประวัติ',
            onPressed: () => setState(() => _index = 3),
          ),
        ),
      );
    }
  }

  void _scheduleNotificationTap() {
    if (!mounted ||
        !_notificationReady ||
        _returningHome ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_returningHome) unawaited(_openNotificationTap());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _openNotificationTap() async {
    if (_checkingNotification) {
      _notificationAgain = true;
      return;
    }
    _checkingNotification = true;
    try {
      final notifications = AppNotifications.instance;
      final chatTap = _pendingNotificationTap?.containsKey('thread') == true
          ? _pendingNotificationTap
          : await notifications.takeChatTap();
      final sosTap = chatTap == null
          ? (_pendingNotificationTap ?? await notifications.takeSosTap())
          : null;
      final tap = chatTap ?? sosTap;
      if (!mounted || tap == null || tap['owner'] != _me.id) {
        _pendingNotificationTap = null;
        return;
      }
      _pendingNotificationTap = tap;
      if (_returningHome ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      final mesh = NearbyMeshService.instance;
      if (mesh.ownerId != _me.id) {
        _pendingNotificationTap = null;
        return;
      }
      ChatContact? contact;
      final thread = chatTap?['thread'] ?? sosTap?['device'];
      if (thread == null ||
          thread.isEmpty ||
          notifications.activeThread == thread ||
          notifications.activeThreadAliases.contains(thread)) {
        _pendingNotificationTap = null;
        return;
      }
      if (chatTap != null) {
        contact = await UnifiedChatService.instance.notificationContact(
          _me.id,
          thread,
          transport: chatTap['transport']!,
        );
      } else if (mesh.inbox.any(
        (m) => m.kind == 'sos' && m.data['origin'] == thread,
      )) {
        contact = ChatContact(name: mesh.chatPeerName(thread), device: thread);
      }
      if (!mounted || tap['owner'] != _me.id || mesh.ownerId != _me.id) return;
      if (_returningHome ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      _pendingNotificationTap = null;
      Navigator.of(context).popUntil((route) => route.isFirst);
      setState(() => _index = 2);
      if (contact != null) {
        final target = contact;
        unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  UnifiedConversationScreen(me: _me, contact: target),
            ),
          ),
        );
      }
    } catch (_) {
      _pendingNotificationTap = null;
      // A missing/deleted contact must not prevent the app from opening.
    } finally {
      _checkingNotification = false;
      if (_notificationAgain) {
        _notificationAgain = false;
        _scheduleNotificationTap();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_returnPolicy.update(state, external: ExternalActivity.active) &&
        mounted) {
      setState(() => _index = 0);
      _returningHome = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
        AppNotifications.instance.activeRoomToken = null;
        AppNotifications.instance.activeThread = null;
        AppNotifications.instance.activeThreadAliases.clear();
        _returningHome = false;
        _scheduleNotificationTap();
      });
    }
    if (state != AppLifecycleState.resumed) {
      unawaited(LocationService.stopPreparing());
    }
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(const LocationService().prepare());
      unawaited(NearbyMeshService.instance.resumeConnections(_me));
      unawaited(
        NetworkService.instance.hasConnection.then((_) {
          if (!mounted) return;
          unawaited(UnifiedChatService.instance.flush());
          CloudInboxService.instance.wake();
        }),
      );
      _scheduleNotificationTap();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppNotifications.instance.taps.removeListener(_scheduleNotificationTap);
    unawaited(LocationService.stopPreparing());
    RescueStatusService.instance.removeListener(_onRescueStatus);
    RescueStatusService.instance.stop();
    UnifiedChatService.instance.stop();
    OfflineMediaService.instance.stop();
    _inboxSubscription?.cancel();
    _nearbyInboxSubscription?.cancel();
    unawaited(SyncService.instance.stop());
    super.dispose();
  }

  void _handleInbox(List<LocalChatConversation> conversations) {
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
                      builder: (_) => UnifiedConversationScreen(
                        me: _me,
                        contact: ChatContact(
                          name: conversation.displayName,
                          user: conversation.peerUserId,
                          conversation: conversation.id,
                        ),
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
    ).push(MaterialPageRoute(builder: (_) => SosScreen(me: _me)));
  }

  Future<void> _openRescue() async {
    if (!_me.isMember) {
      _notice('ต้องสมัครสมาชิกก่อนใช้งาน RESCUE MODE');
      return;
    }

    if (!_me.isVerifiedRescuer) {
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
    ).push(MaterialPageRoute(builder: (_) => RescueScreen(me: _me)));
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    _visitedTabs.add(_index);
    final pages = <Widget>[
      HomeDashboard(
        me: _me,
        onSos: _openSos,
        onRescue: _openRescue,
        onNearby: () => setState(() => _index = 1),
        onChat: () => setState(() => _index = 2),
        unreadCount: _combinedUnread,
        sosRecords: _sosRecords,
      ),
      if (_visitedTabs.contains(1))
        NearbyScreen(me: _me)
      else
        const SizedBox.shrink(),
      if (_visitedTabs.contains(2))
        ChatScreen(me: _me)
      else
        const SizedBox.shrink(),
      if (_visitedTabs.contains(3))
        ProfileScreen(
          me: _me,
          onLogout: widget.onLogout,
          onUpdated: (updated) {
            if (!mounted || updated.id != _me.id) return;
            setState(() => _me = updated);
            unawaited(NearbyMeshService.instance.initializeForUser(updated));
          },
        )
      else
        const SizedBox.shrink(),
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

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({
    super.key,
    required this.me,
    required this.onSos,
    required this.onRescue,
    required this.onNearby,
    required this.onChat,
    required this.unreadCount,
    this.sosRecords,
    this.service,
  });
  final AppUser me;
  final VoidCallback onSos, onRescue, onNearby, onChat;
  final int unreadCount;
  final Stream<List<LocalSosRecord>>? sosRecords;
  final NearbyMeshService? service;

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  NearbyMeshService get _mesh => widget.service ?? NearbyMeshService.instance;
  AppUser get me => widget.me;
  VoidCallback get onSos => widget.onSos;
  VoidCallback get onRescue => widget.onRescue;
  VoidCallback get onNearby => widget.onNearby;
  VoidCallback get onChat => widget.onChat;
  int get unreadCount => widget.unreadCount;
  late Stream<List<LocalSosRecord>> _records;
  String? _ownSignature;

  @override
  void initState() {
    super.initState();
    _records = widget.sosRecords ?? SosRepository().watchForUser(me.id);
    _mesh.addListener(_ownSosChanged);
  }

  void _ownSosChanged() {
    final mesh = _mesh;
    final record = mesh.ownerId == me.id ? mesh.ownSosRecord : null;
    final signature = '${record?.id}:${record?.revision}:${record?.isActive}';
    if (signature == _ownSignature) return;
    _ownSignature = signature;
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant HomeDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      (oldWidget.service ?? NearbyMeshService.instance).removeListener(
        _ownSosChanged,
      );
      _mesh.addListener(_ownSosChanged);
      _ownSignature = null;
    }
    if (oldWidget.me.id != me.id ||
        !identical(oldWidget.sosRecords, widget.sosRecords)) {
      _records = widget.sosRecords ?? SosRepository().watchForUser(me.id);
    }
  }

  @override
  void dispose() {
    _mesh.removeListener(_ownSosChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<LocalSosRecord>>(
    stream: _records,
    builder: (context, snapshot) {
      final mesh = _mesh;
      final cached = mesh.ownerId == me.id ? mesh.ownSosRecord : null;
      final records =
          snapshot.data ?? [if (cached != null && cached.isActive) cached];
      return SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
              children: [
                ListenableBuilder(
                  listenable: _mesh,
                  builder: (context, _) {
                    final mesh = _mesh;
                    final sosActive = records.any((r) => r.isActive);
                    final rescueActive =
                        mesh.ownerId == me.id &&
                        mesh.rescueActive &&
                        me.isVerifiedRescuer;
                    return Row(
                      children: [
                        const Expanded(child: BrandLockup()),
                        if (sosActive || rescueActive) ...[
                          const SizedBox(width: 8),
                          IconButton.filled(
                            tooltip: sosActive
                                ? 'SOS กำลังทำงาน · ดูสถานะ'
                                : 'โหมดกู้ภัยกำลังทำงาน · ดูสถานะ',
                            onPressed: sosActive ? onSos : onRescue,
                            style: IconButton.styleFrom(
                              backgroundColor: sosActive
                                  ? AppColors.sos
                                  : AppColors.rescue,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(48, 48),
                            ),
                            icon: Icon(
                              sosActive
                                  ? Icons.sos_rounded
                                  : Icons.health_and_safety_rounded,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'สวัสดี, ${me.firstName}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _NearbyUrgentRequests(me: me),
                EmergencyHomePanel(
                  me: me,
                  record: records.where((r) => r.isActive).firstOrNull,
                  onDetails: onSos,
                ),
                const SizedBox(height: 16),
                if (records.any((r) => r.isActive))
                  NearbyPeoplePanel(me: me)
                else
                  _ConnectionPanel(onTap: onNearby),
                const SizedBox(height: 12),
                const SizedBox(height: 20),
                Text(
                  'ติดต่อและช่วยเหลือ',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListenableBuilder(
                        listenable: _mesh,
                        builder: (context, _) {
                          final mesh = _mesh;
                          return _ActionRow(
                            icon: Icons.radar_rounded,
                            title: 'บุคคลใกล้เคียง',
                            detail: mesh.connected.isNotEmpty
                                ? 'เชื่อมต่อ ${mesh.connectedDeviceCount} เครื่อง'
                                : mesh.running
                                ? 'กำลังค้นหาอุปกรณ์'
                                : '',
                            color: context.colors.info,
                            onTap: onNearby,
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 74, endIndent: 20),
                      _ActionRow(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'ข้อความ',
                        detail: '',
                        color: context.colors.info,
                        onTap: onChat,
                        count: unreadCount,
                      ),
                      const Divider(height: 1, indent: 74, endIndent: 20),
                      _ActionRow(
                        icon: Icons.health_and_safety_outlined,
                        title: me.isVerifiedRescuer
                            ? 'ศูนย์กู้ภัย'
                            : 'สิทธิ์หน่วยกู้ภัย',
                        detail: '',
                        color: context.colors.rescue,
                        onTap: onRescue,
                      ),
                    ],
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

class _NearbyUrgentRequests extends StatelessWidget {
  const _NearbyUrgentRequests({required this.me});
  final AppUser me;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: NearbyMeshService.instance,
    builder: (context, _) {
      final mesh = NearbyMeshService.instance;
      final cases = mesh.currentSosCases;
      if (cases.isEmpty) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.sos,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.sos),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'SOS ที่ติดต่อได้ · ${cases.length} คำขอ',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            for (final message in cases.take(1))
              ListTile(
                contentPadding: EdgeInsets.zero,
                textColor: Colors.white,
                iconColor: Colors.white,
                leading: const Icon(Icons.sos_rounded, color: Colors.white),
                title: Text(
                  mesh.chatPeerName(message.data['origin'].toString()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  (message.data['data'] as Map)['text']?.toString() ??
                      'ต้องการความช่วยเหลือ',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chat_bubble_outline_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => UnifiedConversationScreen(
                      me: me,
                      contact: ChatContact(
                        name: mesh.chatPeerName(
                          message.data['origin'].toString(),
                        ),
                        device: message.data['origin'].toString(),
                      ),
                    ),
                  ),
                ),
              ),
            if (cases.length > 1)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => NearbyScreen(me: me))),
                child: Text('ดูคำขอทั้งหมด ${cases.length} รายการ'),
              ),
          ],
        ),
      );
    },
  );
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: NearbyMeshService.instance,
    builder: (context, _) {
      final mesh = NearbyMeshService.instance;
      final connected = mesh.connectedDeviceCount;
      return AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  connected > 0 ? Icons.link_rounded : Icons.link_off_rounded,
                  color: context.colors.info,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    connected > 0
                        ? 'เชื่อมต่อแล้ว $connected เครื่อง'
                        : 'ยังไม่ได้เชื่อมต่อกับใคร',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.radar_rounded),
              label: Text(
                connected > 0
                    ? 'ดูอุปกรณ์ที่เชื่อมต่อ'
                    : mesh.running
                    ? 'ดูอุปกรณ์ที่พบ'
                    : 'ค้นหาบุคคลใกล้เคียง',
              ),
            ),
          ],
        ),
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
                if (detail.isNotEmpty) ...[
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
