import 'dart:async';

/// One upstream subscription while visible consumers share its latest snapshot.
/// Releases the upstream and cached data when the last consumer leaves.
class SharedSnapshot<T> {
  SharedSnapshot(this.source);

  final Stream<T> Function() source;
  final _listeners = <MultiStreamController<T>>{};
  StreamSubscription<T>? _subscription;
  T? _latest;
  bool _hasLatest = false;
  int _generation = 0;

  late final Stream<T> stream = Stream<T>.multi((listener) {
    _listeners.add(listener);
    if (_hasLatest) listener.add(_latest as T);
    listener.onCancel = () {
      _listeners.remove(listener);
      if (_listeners.isEmpty) {
        ++_generation;
        final subscription = _subscription;
        _subscription = null;
        _latest = null;
        _hasLatest = false;
        unawaited(subscription?.cancel());
      }
    };
    if (_subscription != null) return;
    final generation = ++_generation;
    _subscription = source().listen(
      (value) {
        if (generation != _generation) return;
        _latest = value;
        _hasLatest = true;
        for (final target in _listeners.toList()) {
          target.add(value);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (generation != _generation) return;
        for (final target in _listeners.toList()) {
          target.addError(error, stack);
        }
      },
      onDone: () {
        if (generation != _generation) return;
        _subscription = null;
        _latest = null;
        _hasLatest = false;
        final targets = _listeners.toList();
        _listeners.clear();
        for (final target in targets) {
          target.close();
        }
      },
    );
  });
}
