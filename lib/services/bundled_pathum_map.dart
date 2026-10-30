import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:latlong2/latlong.dart';

/// Entire street database ships in the APK. No network provider or glyph URL.
class BundledPathumMap {
  BundledPathumMap._(this.index, this.tiles, this.light, this.dark);
  static const folder = 'assets/maps/pathum_thani';
  static const center = LatLng(14.09616, 100.64184);
  static Future<BundledPathumMap>? _cached;
  final Map<String, dynamic> index;
  final Map<vt.TileKey, Uint8List> tiles;
  final vt.Theme light, dark;

  static Future<BundledPathumMap> load() =>
      _cached ??= _load().catchError((Object error, StackTrace stack) {
        _cached = null;
        Error.throwWithStackTrace(error, stack);
      });

  static Future<BundledPathumMap> _load() async {
    final index =
        jsonDecode(await rootBundle.loadString('$folder/index.json'))
            as Map<String, dynamic>;
    final data = await rootBundle.load('$folder/tiles.pack');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (index['format'] != 1 ||
        bytes.length != index['bytes'] ||
        await compute(_digest, bytes) != index['sha256']) {
      throw const FormatException('Offline map integrity check failed');
    }
    final tiles = <vt.TileKey, Uint8List>{};
    for (final raw in index['tiles'] as List) {
      final row = (raw as List).cast<int>();
      if (row.length != 5 ||
          row[3] < 0 ||
          row[4] <= 0 ||
          row[3] + row[4] > bytes.length) {
        throw const FormatException('Invalid offline tile index');
      }
      tiles[vt.TileKey(row[0], row[1], row[2])] = Uint8List.sublistView(
        bytes,
        row[3],
        row[3] + row[4],
      );
    }
    Future<vt.Theme> theme(String mode) async => const vt.ThemeReader().read(
      (jsonDecode(await rootBundle.loadString('$folder/$mode.json')) as Map)
          .cast<String, Object?>(),
      id: '${index['id']}-$mode',
    );
    return BundledPathumMap._(
      index,
      tiles,
      await theme('light'),
      await theme('dark'),
    );
  }

  static String _digest(Uint8List bytes) => sha256.convert(bytes).toString();

  vt.MemoryVectorTileProvider provider() => vt.MemoryVectorTileProvider(
    tiles: tiles,
    minimumZoom: index['minzoom'] as int,
    maximumZoom: index['maxzoom'] as int,
    cacheKey: index['sha256'] as String,
  );

  /// The bounding rectangle includes edge context; only this is guaranteed.
  static bool contains(LatLng point) =>
      point.latitude >= 13.9112736 &&
      point.latitude <= 14.2810439 &&
      point.longitude >= 100.3266046 &&
      point.longitude <= 100.9570756;
}
