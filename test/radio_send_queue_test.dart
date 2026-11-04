import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:offgrid_sos/services/radio_send_queue.dart';

void main() {
  test(
    'SOS controls overtake waiting media and frames stay serialized',
    () async {
      final queue = RadioSendQueue();
      final held = Completer<void>();
      final order = <String>[];
      final first = queue.add('a', () async {
        order.add('first');
        await held.future;
      }, priority: false);
      final bulk = queue.add('a', () async {
        order.add('video');
      }, priority: false);
      final sos = queue.add('a', () async {
        order.add('sos');
      });
      final receipt = queue.add('a', () async {
        order.add('receipt');
      });
      expect(order, ['first']);
      held.complete();
      await Future.wait([first, bulk, sos, receipt]);
      expect(order, ['first', 'sos', 'receipt', 'video']);
    },
  );
  test('blocked endpoint does not block a different phone', () async {
    final queue = RadioSendQueue();
    final held = Completer<void>();
    final first = queue.add('a', () => held.future);
    var done = false;
    await queue.add('b', () async {
      done = true;
    });
    expect(done, isTrue);
    held.complete();
    await first;
  });
  test('transport failure completes caller and next frame proceeds', () async {
    final queue = RadioSendQueue();
    await expectLater(
      queue.add('a', () async {
        throw StateError('disconnect');
      }),
      throwsStateError,
    );
    var done = false;
    await queue.add('a', () async {
      done = true;
    });
    expect(done, isTrue);
  });
}
