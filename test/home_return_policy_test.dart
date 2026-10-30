import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offgrid_sos/services/home_return_policy.dart';

void main() {
  test(
    'new launch and permission dialogs do not trigger duplicate navigation',
    () {
      final p = HomeReturnPolicy();
      expect(p.update(AppLifecycleState.resumed), isFalse);
      p.update(AppLifecycleState.inactive);
      expect(p.update(AppLifecycleState.resumed), isFalse);
    },
  );
  test('real background returns home once on resume', () {
    final p = HomeReturnPolicy();
    p.update(AppLifecycleState.inactive);
    p.update(AppLifecycleState.hidden);
    p.update(AppLifecycleState.paused);
    p.update(AppLifecycleState.hidden);
    p.update(AppLifecycleState.inactive);
    expect(p.update(AppLifecycleState.resumed), isTrue);
    expect(p.update(AppLifecycleState.resumed), isFalse);
  });
  test('camera and picker return to originating screen', () async {
    final p = HomeReturnPolicy();
    await ExternalActivity.run(() async {
      expect(ExternalActivity.active, isTrue);
      p.update(AppLifecycleState.paused, external: ExternalActivity.active);
      expect(p.update(AppLifecycleState.resumed), isFalse);
    });
    expect(ExternalActivity.active, isFalse);
    p.update(AppLifecycleState.paused);
    expect(p.update(AppLifecycleState.resumed), isTrue);
  });
  test('failed external launch releases guard', () async {
    await expectLater(
      ExternalActivity.run<void>(() async => throw StateError('failed')),
      throwsStateError,
    );
    expect(ExternalActivity.active, isFalse);
  });
}
