import 'package:flutter/material.dart';
import '../app/theme.dart';
import 'app_card.dart';

enum PeerKind { sos, rescue, normal }

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.kind,
    required this.name,
    required this.detail,
    this.description,
    this.onTap,
    this.actionLabel,
  });

  final PeerKind kind;
  final String name;
  final String detail;
  final String? description;
  final VoidCallback? onTap;
  final String? actionLabel;

  IconData get _icon => switch (kind) {
    PeerKind.sos => Icons.warning_amber_rounded,
    PeerKind.rescue => Icons.health_and_safety_outlined,
    PeerKind.normal => Icons.person_outline_rounded,
  };

  String get _code => switch (kind) {
    PeerKind.sos => 'SOS',
    PeerKind.rescue => 'RESCUE',
    PeerKind.normal => 'USER',
  };

  String get _defaultDescription => switch (kind) {
    PeerKind.sos => 'ต้องการความช่วยเหลือ',
    PeerKind.rescue => 'หน่วยกู้ภัย',
    PeerKind.normal => 'ผู้ใช้ทั่วไป · พร้อมช่วย Relay',
  };

  Color get _color => switch (kind) {
    PeerKind.sos => AppColors.sos,
    PeerKind.rescue => AppColors.rescue,
    PeerKind.normal => AppColors.muted,
  };

  @override
  Widget build(BuildContext context) {
    final desc = description ?? _defaultDescription;
    return Semantics(
      button: onTap != null,
      label: '$_code $name, $desc, $detail',
      hint: onTap != null ? 'แตะสองครั้งเพื่อเปิดการสนทนา' : null,
      child: AppCard(
        borderColor: _color.withValues(alpha: .85),
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _color.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_icon, color: _color, size: 27),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _code,
                                style: TextStyle(
                                  color: _color,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Text(
                                detail,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            desc,
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (actionLabel != null && onTap != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onTap,
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 18,
                      ),
                      label: Text(actionLabel!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
