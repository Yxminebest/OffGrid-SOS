import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../app/theme_controller.dart';
import 'app_card.dart';

class ThemeModeButton extends StatelessWidget {
  const ThemeModeButton({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ThemeControllerScope.of(context),
    builder: (context, _) {
      final controller = ThemeControllerScope.of(context);
      final dark = controller.mode == ThemeMode.dark;
      return IconButton.outlined(
        tooltip: dark ? 'เปลี่ยนเป็นโหมดสว่าง' : 'เปลี่ยนเป็นโหมดมืด',
        onPressed: () =>
            controller.setMode(dark ? ThemeMode.light : ThemeMode.dark),
        icon: Icon(
          dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          size: 21,
        ),
        style: IconButton.styleFrom(
          side: BorderSide(color: context.colors.border),
          foregroundColor: context.colors.text,
          backgroundColor: context.colors.surface,
        ),
      );
    },
  );
}

class AppearancePicker extends StatelessWidget {
  const AppearancePicker({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('รูปแบบการแสดงผล', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 5),
      Text(
        'เลือกแบบที่สบายตา แอปจะจำให้คุณ',
        style: TextStyle(color: context.colors.muted, fontSize: 12),
      ),
      const SizedBox(height: 12),
      ListenableBuilder(
        listenable: ThemeControllerScope.of(context),
        builder: (context, _) => AppCard(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              Expanded(
                child: _ModeOption(
                  mode: ThemeMode.light,
                  label: 'สว่าง',
                  icon: Icons.light_mode_outlined,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ModeOption(
                  mode: ThemeMode.dark,
                  label: 'มืด',
                  icon: Icons.dark_mode_outlined,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.mode,
    required this.label,
    required this.icon,
  });
  final ThemeMode mode;
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final controller = ThemeControllerScope.of(context);
    final selected = controller.mode == mode;
    return Semantics(
      selected: selected,
      button: true,
      label: 'โหมด$label',
      child: Material(
        color: selected ? context.colors.surfaceSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: () => controller.setMode(mode),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: selected ? context.colors.info : context.colors.muted,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? context.colors.info
                          : context.colors.muted,
                    ),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 7),
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: context.colors.info,
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
