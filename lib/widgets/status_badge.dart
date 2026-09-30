import 'package:flutter/material.dart';
import '../app/theme.dart';
import 'app_card.dart';

enum PeerKind { sos, rescue, normal }

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.kind,
    required this.name,
    this.detail,
    this.onTap,
    this.actionLabel,
  });

  final PeerKind kind;
  final String name;
  final String? detail;
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

  String get _description => switch (kind) {
        PeerKind.sos => 'ต้องการความช่วยเหลือ',
        PeerKind.rescue => 'หน่วยกู้ภัย',
        PeerKind.normal => 'ผู้ใช้ทั่วไป',
      };

  Color get _color => switch (kind) {
        PeerKind.sos => AppColors.sos,
        PeerKind.rescue => AppColors.rescue,
        PeerKind.normal => AppColors.muted,
      };

  @override
  Widget build(BuildContext context) {
    final label = '$name, $_code, $_description${detail == null ? '' : ', $detail'}';
    return Semantics(
      button: onTap != null,
      label: label,
      hint: onTap != null ? 'แตะสองครั้งเพื่อเปิดการสนทนา' : null,
      child: AppCard(
        borderColor: _color.withOpacity(.8),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _color.withOpacity(.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(_icon, color: _color, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(_code,
                                style: TextStyle(
                                  color: _color,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  letterSpacing: .4,
                                )),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.text,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 17,
                                  )),
                            ),
                          ]),
                          const SizedBox(height: 3),
                          Text(_description,
                              style: const TextStyle(
                                  color: AppColors.text, fontSize: 15)),
                          if (detail != null) ...[
                            const SizedBox(height: 3),
                            Text(detail!,
                                style: const TextStyle(
                                    color: AppColors.muted, fontSize: 14)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (onTap != null && actionLabel != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
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
