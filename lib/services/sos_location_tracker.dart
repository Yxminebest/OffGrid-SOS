import 'dart:async';
import 'package:geolocator/geolocator.dart';

import '../data/models/local_sos_record.dart';
import '../data/repositories/sos_repository.dart';
import 'location_service.dart';
import 'nearby_mesh_service.dart';

/// Attach the first real fix promptly, then improve it without delaying SOS.
class SosLocationTracker {
  SosLocationTracker(this.location, this.repository, this.mesh);
  final LocationService location;
  final SosRepository repository;
  final NearbyMeshService mesh;
  StreamSubscription<SavedLocation>? _subscription;
  Timer? _deadline;
  int _generation = 0;
  Future<void> _work = Future.value();

  void start(LocalSosRecord record) {
    cancel();
    final generation = _generation;
    SavedLocation? accepted;
    _subscription = location.emergencyLocations().listen((fix) {
      _work = _work
          .then((_) async {
            if (generation != _generation ||
                mesh.ownerId != record.ownerLocalId) {
              return;
            }
            // Cache may be stale but is explicitly labelled. A live fix replaces it.
            final moved =
                accepted != null &&
                Geolocator.distanceBetween(
                      accepted!.latitude,
                      accepted!.longitude,
                      fix.latitude,
                      fix.longitude,
                    ) >
                    LocationFixWindow.accuracy(accepted!) +
                        LocationFixWindow.accuracy(fix);
            if (!moved &&
                accepted != null &&
                accepted!.age < const Duration(seconds: 8) &&
                !accepted!.isLastKnown &&
                (fix.isLastKnown ||
                    LocationFixWindow.accuracy(fix) >=
                        LocationFixWindow.accuracy(accepted!))) {
              return;
            }
            final updated = await repository.updateLocation(
              record,
              fix,
              allowLastKnown: true,
            );
            if (updated == null || generation != _generation) return;
            accepted = fix;
            await mesh.publishSosRecord(updated);
          })
          .catchError((Object _) {});
    }, onError: (Object _) {});
    _deadline = Timer(const Duration(seconds: 35), cancel);
  }

  void cancel() {
    ++_generation;
    _deadline?.cancel();
    _deadline = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}
