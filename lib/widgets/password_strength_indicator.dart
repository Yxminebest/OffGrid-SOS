import 'package:flutter/material.dart';

import '../app/theme.dart';

class PasswordStrengthIndicator extends StatelessWidget {
  const PasswordStrengthIndicator({super.key, required this.password});

  final String password;

  int _score(String value) {
    if (value.isEmpty) return 0;

    var score = 0;
    if (value.length >= 8) score += 1;
    if (value.length >= 12) score += 1;
    if (RegExp(r'[a-z]').hasMatch(value) && RegExp(r'[A-Z]').hasMatch(value)) {
      score += 1;
    }
    if (RegExp(r'\d').hasMatch(value)) score += 1;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score += 1;
    return score.clamp(0, 5).toInt();
  }

  String _label(int score) {
    if (password.isEmpty) return 'ยังไม่ได้กรอกรหัสผ่าน';
    if (score <= 1) return 'ความแข็งแรง: อ่อน';
    if (score == 2) return 'ความแข็งแรง: พอใช้';
    if (score <= 4) return 'ความแข็งแรง: ดี';
    return 'ความแข็งแรง: แข็งแรง';
  }

  Color _color(int score) {
    if (score <= 1) return AppColors.error;
    if (score == 2) return AppColors.pending;
    if (score <= 4) return AppColors.info;
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    final score = _score(password);
    final color = _color(score);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: password.isEmpty ? 0 : score / 5,
          minHeight: 6,
          color: color,
          backgroundColor: AppColors.border,
        ),
        const SizedBox(height: 6),
        Text(
          _label(score),
          style: TextStyle(
            color: password.isEmpty ? AppColors.muted : color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'ขั้นต่ำ 8 ตัวอักษร • แนะนำให้มีตัวพิมพ์ใหญ่/เล็ก ตัวเลข และสัญลักษณ์',
          style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.35),
        ),
      ],
    );
  }
}
