import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:offgrid_sos/services/shared_snapshot.dart';

void main() {
  test('shares one upstream and replays latest to a later consumer', () async {
    var starts = 0;
    var stops = 0;
    final source = StreamController<int>.broadcast(
      onListen: () => starts++,
      onCancel: () => stops++,
    );
    final shared = SharedSnapshot(() => source.stream);
    final first = StreamIterator(shared.stream);
    final firstValue = first.moveNext();
    source.add(7);
    expect(await firstValue, isTrue);
    expect(first.current, 7);
    final second = StreamIterator(shared.stream);
    expect(await second.moveNext(), isTrue);
    expect(second.current, 7);
    expect(starts, 1);
    await first.cancel();
    expect(stops, 0);
    final next = second.moveNext();
    source.add(8);
    expect(await next, isTrue);
    expect(second.current, 8);
    await second.cancel();
    expect(stops, 1);
    await source.close();
  });

  test('reopening after all consumers leave reads fresh data', () async {
    var starts = 0;
    final shared = SharedSnapshot(() => Stream.value(++starts));
    expect(await shared.stream.first, 1);
    expect(await shared.stream.first, 2);
  });

  test('forwards errors and later updates to every consumer', () async {
    final source = StreamController<int>();
    final shared = SharedSnapshot(() => source.stream);
    final a = <Object>[];
    final b = <Object>[];
    final one = shared.stream.listen(a.add, onError: (Object e) => a.add(e));
    final two = shared.stream.listen(b.add, onError: (Object e) => b.add(e));
    final error = StateError('temporary read failure');
    source.addError(error);
    source.add(9);
    await Future<void>.delayed(Duration.zero);
    expect(a, [error, 9]);
    expect(b, [error, 9]);
    await one.cancel();
    await two.cancel();
    await source.close();
  });

  test('source completion closes all consumers', () async {
    final source = StreamController<int>();
    final shared = SharedSnapshot(() => source.stream);
    final a = shared.stream.toList();
    final b = shared.stream.toList();
    source.add(2);
    await source.close();
    expect(await a, [2]);
    expect(await b, [2]);
  });
}
