import '../app/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:latlong2/latlong.dart';
import '../services/bundled_pathum_map.dart';
import 'location_actions.dart';

/// Real bundled cartography, not a network screenshot or a decorative fake map.
class ChatLocationPreview extends StatefulWidget {
  const ChatLocationPreview({
    super.key,
    required this.lat,
    required this.lng,
    this.accuracy,
  });
  final double lat, lng;
  final double? accuracy;
  @override
  State<ChatLocationPreview> createState() => _ChatLocationPreviewState();
}

class _ChatLocationPreviewState extends State<ChatLocationPreview> {
  late final map = BundledPathumMap.load();
  vt.MemoryVectorTileProvider? provider;
  @override
  void dispose() {
    provider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final point = LatLng(widget.lat, widget.lng);
    final inside = BundledPathumMap.contains(point);
    return InkWell(
      onTap: () => LocationActions.show(
        context,
        widget.lat,
        widget.lng,
        accuracy: widget.accuracy,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 320,
          height: 170,
          child: FutureBuilder<BundledPathumMap>(
            future: map,
            builder: (ctx, snapshot) {
              if (!snapshot.hasData) {
                return Center(
                  child: Text(
                    snapshot.hasError
                        ? 'แตะเพื่อเปิดพิกัด'
                        : 'กำลังเปิดแผนที่ในเครื่อง…',
                  ),
                );
              }
              provider ??= snapshot.data!.provider();
              return Stack(
                children: [
                  IgnorePointer(
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: inside ? point : BundledPathumMap.center,
                        initialZoom: inside ? 14.5 : 9,
                        minZoom: 8,
                        maxZoom: 19,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.none,
                        ),
                      ),
                      children: [
                        vt.VectorTileLayer(
                          tileOffset: vt.TileOffset.none,
                          theme: Theme.of(context).brightness == Brightness.dark
                              ? snapshot.data!.dark
                              : snapshot.data!.light,
                          tileProviders: vt.TileProviders({
                            'shortbread': provider!,
                          }),
                          concurrency: 1,
                          memoryCacheMaxBytes: 2 * 1024 * 1024,
                          rasterCacheMaxBytes: 4 * 1024 * 1024,
                          diskCacheMaximumSizeInBytes: 0,
                        ),
                        if (inside)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: point,
                                width: 42,
                                height: 42,
                                child: const Icon(
                                  Icons.location_on,
                                  color: AppColors.mapPin,
                                  size: 36,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 6,
                    bottom: 5,
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surface,
                      child: const Text(
                        '© OpenStreetMap contributors',
                        style: TextStyle(fontSize: 8),
                      ),
                    ),
                  ),
                  if (!inside)
                    Center(
                      child: Material(
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('พิกัดอยู่นอกแผนที่ปทุมธานี'),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
