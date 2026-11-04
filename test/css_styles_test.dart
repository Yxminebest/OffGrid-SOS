import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../tool/generate_styles.dart';

void main() {
  final css = File('styles/app.css').readAsStringSync();
  final templates = {
    for (final name in ['app_palette.dart', 'style_tokens.dart'])
      name: File('tool/style_templates/$name.template').readAsStringSync(),
  };

  test('CSS is the actual source for checked-in native styles', () {
    final outputs = compileStyles(css, templates);
    for (final output in outputs.entries) {
      expect(
        File(
          'lib/app/${output.key}',
        ).readAsStringSync().replaceAll('\r\n', '\n'),
        output.value.replaceAll('\r\n', '\n'),
        reason: 'Run dart run tool/generate_styles.dart',
      );
    }
  });

  test('editing CSS changes Flutter brand color and shared button shape', () {
    final changed = css
        .replaceFirst('--color-brand: #F4C84B;', '--color-brand: #123456;')
        .replaceFirst('--control-radius: 16.0px;', '--control-radius: 18px;');
    final outputs = compileStyles(changed, templates);
    expect(outputs['app_palette.dart'], contains('brand = Color(0xFF123456)'));
    expect(outputs['style_tokens.dart'], contains('controlRadius = 18.0'));
    expect(outputs['app_palette.dart'], contains('Color(0xFF191710)'));
  });

  test(
    'CSS aliases follow their source and circular references are rejected',
    () {
      final changed = css.replaceFirst(
        '--color-sos: #C93643;',
        '--color-sos: #AA1122;',
      );
      final parsed = parseStyleVariables(changed);
      expect(parsed['root.color-error'], 'FFAA1122');
      expect(
        () => parseStyleVariables(
          css.replaceFirst(
            '--color-sos: #C93643;',
            '--color-sos: var(--color-error);',
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'invalid, unused and unsupported CSS fails instead of silently being ignored',
    () {
      expect(
        () => compileStyles(css.replaceFirst('#F4C84B', 'blue'), templates),
        throwsFormatException,
      );
      expect(
        () => compileStyles(
          css.replaceFirst(
            '--control-radius: 16.0px;',
            '--control-radius: -2px;',
          ),
          templates,
        ),
        throwsFormatException,
      );
      expect(
        () => compileStyles(
          css.replaceFirst(':root {', ':root {\n --typo-size: 4px;'),
          templates,
        ),
        throwsFormatException,
      );
      expect(
        () => compileStyles('$css\nbutton { color: red; }', templates),
        throwsFormatException,
      );
    },
  );
}
