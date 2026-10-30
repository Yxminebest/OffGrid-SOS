import 'package:flutter/material.dart';
import '../../models/user.dart';
import '../../services/location_service.dart';
import '../../services/nearby_mesh_service.dart';
import '../../services/unified_chat_service.dart';
import 'unified_conversation_screen.dart';

/// Compatibility entry used by SOS/rescue/discovery: all open the same room UI.
class NearbyConversationScreen extends StatefulWidget {
  const NearbyConversationScreen({
    super.key,
    required this.me,
    required this.peerId,
    required this.name,
    this.caseId,
    this.service,
    this.initialDraft,
    this.locationService = const LocationService(),
  });
  final AppUser me;
  final String peerId, name;
  final String? caseId, initialDraft;
  final NearbyMeshService? service;
  final LocationService locationService;
  @override
  State<NearbyConversationScreen> createState() => _UnifiedNearbyEntryState();
}

class _UnifiedNearbyEntryState extends State<NearbyConversationScreen> {
  late final unified = widget.service == null
      ? UnifiedChatService.instance
      : UnifiedChatService(
          local: widget.service!.localDatabase,
          mesh: widget.service,
          online: () => false,
        );
  @override
  void dispose() {
    if (widget.service != null) unified.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UnifiedConversationScreen(
    me: widget.me,
    contact: ChatContact(
      name: unified.mesh.chatPeerName(widget.peerId, fallback: widget.name),
      device: widget.peerId,
      user: unified.mesh.peerForDevice(widget.peerId)?.userId,
    ),
    service: unified,
    caseId: widget.caseId,
    initialDraft: widget.initialDraft,
    gps: widget.locationService,
  );
}
