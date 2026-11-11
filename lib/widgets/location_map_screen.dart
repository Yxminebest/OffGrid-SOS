import '../app/app_palette.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:latlong2/latlong.dart';
import '../services/bundled_pathum_map.dart';
import '../services/location_service.dart';
import 'offline_location_guide.dart';

/// Real regional streets and GPS; all cartography is installed with the app.
class LocationMapScreen extends StatefulWidget {
  const LocationMapScreen({
    super.key,
    required this.latitude,
    required this.longitude,
    this.tileProvider,
    this.targetAccuracy,
    this.locationService = const LocationService(
      gpsTimeout: Duration(seconds: 45),
    ),
  }) : overview = false;

  const LocationMapScreen.overview({
    super.key,
    this.locationService = const LocationService(
      gpsTimeout: Duration(seconds: 45),
    ),
    this.tileProvider,
  }) : targetAccuracy = null,
       latitude = 14.09616,
       longitude = 100.64184,
       overview = true;

  final double latitude, longitude;
  final double? targetAccuracy;
  final bool overview;

  /// Deterministic injected raster tiles for widget tests only.
  final TileProvider? tileProvider;
  final LocationService locationService;
  @override
  State<LocationMapScreen> createState() => _LocationMapScreenState();
}

class _LocationMapScreenState extends State<LocationMapScreen>
    with WidgetsBindingObserver {
  StreamSubscription<SavedLocation>? _gpsWatch;
  int _gpsGeneration = 0;
  final _controller = MapController();
  late Future<BundledPathumMap> _map;
  vt.MemoryVectorTileProvider? _provider;
  bool _tileFailed = false, _locating = false;
  bool _mapReady = false;
  bool _gpsSettings = false, _permissionSettings = false;
  int _attempt = 0;
  SavedLocation? _position;
  String? _gpsMessage;
  LatLng get _point => LatLng(widget.latitude, widget.longitude);
  bool get _inside => BundledPathumMap.contains(_point);
  bool get _testTiles => widget.tileProvider != null;
  bool get _regionalView => widget.overview || (!_inside && !_testTiles);
  LatLngBounds get _bounds => LatLngBounds(
    const LatLng(13.9112736, 100.3266046),
    const LatLng(14.2810439, 100.9570756),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _map = _testTiles
        ? Future.error(StateError('injected tiles'))
        : BundledPathumMap.load();
    // Injected tiles do not use the bundle FutureBuilder.
    if (_testTiles) _map.ignore();
  }

  void _openOfflineGuide() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => OfflineLocationGuide(
        latitude: widget.latitude,
        longitude: widget.longitude,
      ),
    ),
  );

  Future<void> _locate() async {
    if (_locating) return;
    // A generation token prevents a delayed GPS result from reviving a cancelled watch.
    final generation = ++_gpsGeneration;
    await _gpsWatch?.cancel();
    if (!mounted) return;
    setState(() {
      _locating = true;
      _gpsMessage =
          'กำลังเก็บพิกัดหลายครั้งเพื่อเลือกค่าที่ดีที่สุด กรุณารอในที่โล่ง';
      _gpsSettings = _permissionSettings = false;
    });
    try {
      final service = widget.locationService;
      final enabled = await service.isEnabled();
      final blocked = await service.isPermissionBlocked();
      final position = await service.getLatestLocation();
      if (!mounted || generation != _gpsGeneration) return;
      final valid =
          position != null &&
          position.latitude.isFinite &&
          position.longitude.isFinite &&
          position.latitude.abs() <= 90 &&
          position.longitude.abs() <= 180;
      setState(() {
        _gpsSettings = !enabled;
        _permissionSettings = blocked;
        _position = valid ? position : null;
        _gpsMessage = !enabled
            ? 'GPS ปิดอยู่ เปิดตำแหน่งแล้วกดหาตำแหน่งอีกครั้ง'
            : blocked
            ? 'ยังไม่ได้รับสิทธิ์ตำแหน่ง เปิดสิทธิ์ในการตั้งค่าแอป'
            : !valid
            ? 'ยังหาตำแหน่งไม่ได้ อนุญาตตำแหน่งและลองใหม่ในที่โล่ง'
            : null;
      });
      if (enabled && !blocked) {
        _gpsWatch = service.watchLocations().listen(
          (next) {
            if (mounted &&
                generation == _gpsGeneration &&
                LocationFixWindow.valid(next)) {
              setState(() => _position = next);
            }
          },
          onError: (Object _) {
            if (mounted && generation == _gpsGeneration) {
              setState(() => _gpsMessage = 'อัปเดต GPS ไม่ได้ กดหาตำแหน่งใหม่');
            }
          },
        );
      }
      if (valid) {
        final point = LatLng(position.latitude, position.longitude);
        if (BundledPathumMap.contains(point) || _testTiles) {
          if (_mapReady) {
            _controller.move(
              point,
              (position.accuracyMeters ?? 100) > 30 ? 15 : 17,
            );
          }
        } else {
          setState(
            () => _gpsMessage =
                'ตำแหน่งของคุณอยู่นอกชุดแผนที่ปทุมธานี ยังอ่านและคัดลอกพิกัดได้',
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _gpsMessage = 'อ่าน GPS ไม่สำเร็จ กรุณาลองอีกครั้ง');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _onTileError() {
    if (_tileFailed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_tileFailed) setState(() => _tileFailed = true);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _retry() => setState(() {
    _tileFailed = false;
    _attempt++;
    if (!_testTiles) _map = BundledPathumMap.load();
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _gpsGeneration++;
      unawaited(_gpsWatch?.cancel());
      _gpsWatch = null;
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gpsGeneration++;
    unawaited(_gpsWatch?.cancel());
    _controller.dispose();
    _provider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    final coordinates =
        '${widget.latitude.toStringAsFixed(6)}, ${widget.longitude.toStringAsFixed(6)}';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.overview ? 'แผนที่ปทุมธานี' : 'ตำแหน่งบนแผนที่'),
        actions: [
          if (!widget.overview)
            IconButton(
              tooltip: 'ระยะและทิศทางออฟไลน์',
              icon: const Icon(Icons.explore_outlined),
              onPressed: _openOfflineGuide,
            ),
          IconButton(
            tooltip: 'ข้อมูลแผนที่',
            icon: const Icon(Icons.info_outline),
            onPressed: _about,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: _testTiles
                  ? _canvas(null)
                  : FutureBuilder<BundledPathumMap>(
                      future: _map,
                      builder: (context, snapshot) {
                        if (snapshot.hasData) return _canvas(snapshot.data!);
                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'เปิดชุดแผนที่ในเครื่องไม่ได้ พิกัดยังอ่านและคัดลอกได้',
                                  ),
                                  TextButton(
                                    onPressed: _retry,
                                    child: const Text('ลองเปิดแผนที่อีกครั้ง'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text('กำลังเปิดแผนที่จากเครื่อง…'),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Flexible(
              flex: 2,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'ปทุมธานี · แผนที่ออฟไลน์ติดตั้งแล้ว',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    if (!widget.overview) ...[
                      const Text('หมุดสีแดง: พิกัดที่บันทึกไว้'),
                      SelectableText(coordinates),
                      Text(
                        widget.targetAccuracy != null &&
                                widget.targetAccuracy!.isFinite &&
                                widget.targetAccuracy! > 0
                            ? 'ความคลาดเคลื่อนฝั่งผู้ส่งประมาณ ${widget.targetAccuracy!.round()} ม.'
                            : 'ไม่มีค่าความคลาดเคลื่อนของหมุดที่บันทึกไว้',
                      ),
                      if (!_inside && !_testTiles)
                        const Text(
                          'หมุดนี้อยู่นอกชุดแผนที่ปทุมธานี แสดงภาพรวมจังหวัดแทน',
                        ),
                    ],
                    if (_tileFailed) ...[
                      const Text(
                        'โหลดภาพแผนที่บางส่วนไม่ได้ พิกัดยังอ่านและคัดลอกได้',
                      ),
                      TextButton(
                        onPressed: _retry,
                        child: const Text('ลองโหลดแผนที่อีกครั้ง'),
                      ),
                    ],
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _locating ? null : _locate,
                      icon: _locating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                      label: Text(
                        _locating ? 'กำลังหา GPS…' : 'หาตำแหน่งของฉัน (GPS)',
                      ),
                    ),
                    if (_gpsMessage != null)
                      Text(_gpsMessage!, semanticsLabel: _gpsMessage),
                    if (_gpsSettings)
                      TextButton(
                        onPressed: widget.locationService.openGpsSettings,
                        child: const Text('เปิดการตั้งค่า GPS'),
                      ),
                    if (_permissionSettings)
                      TextButton(
                        onPressed:
                            widget.locationService.openPermissionSettings,
                        child: const Text('เปิดสิทธิ์ตำแหน่ง'),
                      ),
                    if (position != null) ...[
                      const Text(
                        'วงกลมแสดงความไม่แน่นอนของ GPS ไม่ใช่ระยะที่คุณเดิน',
                      ),
                      if (LocationFixWindow.accuracy(position) > 30)
                        const Text(
                          'GPS ยังหยาบ: เปิดสิทธิ์ตำแหน่งแบบแม่นยำ และลองรับใหม่ในที่โล่ง หมุดอาจคลาดเคลื่อนแม้อยู่กับที่',
                        ),
                      if (LocationFixWindow.accuracy(position) > 30)
                        TextButton(
                          onPressed:
                              widget.locationService.openPermissionSettings,
                          child: const Text('ตรวจสิทธิ์ตำแหน่งแบบแม่นยำ'),
                        ),
                      Text(
                        position.isLastKnown
                            ? 'หมุดสีเทา: ตำแหน่งล่าสุดที่เครื่องจำได้ (ไม่ใช่ GPS ปัจจุบัน)'
                            : 'หมุดสีน้ำเงิน: ตำแหน่งของคุณ',
                      ),
                      SelectableText(
                        '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
                      ),
                      Text(
                        'เวลาพิกัด: ${_time(position.recordedAt)}${position.accuracyMeters == null ? '' : ' · คลาดเคลื่อนประมาณ ${position.accuracyMeters!.round()} ม.'}',
                      ),
                      TextButton.icon(
                        onPressed: () => _copy(
                          '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
                        ),
                        icon: const Icon(Icons.copy),
                        label: const Text('คัดลอกตำแหน่งของฉัน'),
                      ),
                    ],
                    if (!widget.overview)
                      OutlinedButton.icon(
                        onPressed: () => _copy(coordinates),
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('คัดลอกพิกัด'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _canvas(BundledPathumMap? data) {
    if (data != null) _provider ??= data.provider();
    final position = _position;
    final center = (_inside || _testTiles) ? _point : BundledPathumMap.center;
    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            onMapReady: () => _mapReady = true,
            initialCenter: center,
            initialCameraFit: _regionalView
                ? CameraFit.bounds(
                    bounds: _bounds,
                    padding: const EdgeInsets.all(20),
                  )
                : null,
            initialZoom: widget.overview || (!_inside && !_testTiles)
                ? 10.5
                : 16,
            minZoom: _testTiles ? 2 : 8,
            maxZoom: 19,
            cameraConstraint: _testTiles
                ? const CameraConstraint.unconstrained()
                : CameraConstraint.containCenter(
                    bounds: LatLngBounds(
                      const LatLng(13.9112736, 100.3266046),
                      const LatLng(14.2810439, 100.9570756),
                    ),
                  ),
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          ),
          children: [
            if (_testTiles)
              TileLayer(
                key: ValueKey(_attempt),
                tileProvider: widget.tileProvider,
                maxNativeZoom: 19,
                panBuffer: 0,
                errorTileCallback: (_, _, _) => _onTileError(),
              )
            else
              vt.VectorTileLayer(
                // Our bundled style uses XYZ/256px zooms, including zoom 8.
                tileOffset: vt.TileOffset.none,
                theme: Theme.of(context).brightness == Brightness.dark
                    ? data!.dark
                    : data!.light,
                tileProviders: vt.TileProviders({'shortbread': _provider!}),
                concurrency: 1,
                memoryCacheMaxBytes: 12 * 1024 * 1024,
                rasterCacheMaxBytes: 32 * 1024 * 1024,
                diskCacheMaximumSizeInBytes: 0,
              ),
            if (position != null &&
                !position.isLastKnown &&
                (position.accuracyMeters ?? 0) > 0)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: LatLng(position.latitude, position.longitude),
                    radius: position.accuracyMeters!.clamp(1, 5000),
                    useRadiusInMeter: true,
                    color: Colors.blue.withValues(alpha: .12),
                    borderColor: Colors.blue.withValues(alpha: .4),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
            if (!widget.overview &&
                widget.targetAccuracy != null &&
                widget.targetAccuracy!.isFinite &&
                widget.targetAccuracy! > 0)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _point,
                    radius: widget.targetAccuracy!.clamp(1, 5000),
                    useRadiusInMeter: true,
                    color: AppColors.mapPin.withValues(alpha: .10),
                    borderColor: AppColors.mapPin.withValues(alpha: .4),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (!widget.overview)
                  Marker(
                    point: _point,
                    width: 56,
                    height: 56,
                    alignment: Alignment.topCenter,
                    child: const Icon(
                      Icons.location_on,
                      size: 52,
                      color: AppColors.mapPin,
                      semanticLabel: 'ตำแหน่งที่บันทึกไว้',
                    ),
                  ),
                if (position != null)
                  Marker(
                    point: LatLng(position.latitude, position.longitude),
                    width: 28,
                    height: 28,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: position.isLastKnown ? Colors.grey : Colors.blue,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: Icon(
                        Icons.person,
                        size: 17,
                        color: Colors.white,
                        semanticLabel: position.isLastKnown
                            ? 'ตำแหน่ง GPS เก่า'
                            : 'ตำแหน่งของคุณ',
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Card(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'ซูมเข้า',
                  icon: const Icon(Icons.add),
                  onPressed: () => _zoom(1),
                ),
                IconButton(
                  tooltip: 'ซูมออก',
                  icon: const Icon(Icons.remove),
                  onPressed: () => _zoom(-1),
                ),
                IconButton(
                  tooltip: 'กลับไปยังหมุด',
                  icon: const Icon(Icons.center_focus_strong),
                  onPressed: () {
                    if (position != null &&
                        (BundledPathumMap.contains(
                              LatLng(position.latitude, position.longitude),
                            ) ||
                            _testTiles)) {
                      _controller.move(
                        LatLng(position.latitude, position.longitude),
                        (position.accuracyMeters ?? 100) > 30 ? 15 : 17,
                      );
                    } else if (_regionalView) {
                      _controller.fitCamera(
                        CameraFit.bounds(
                          bounds: _bounds,
                          padding: const EdgeInsets.all(20),
                        ),
                      );
                    } else {
                      _controller.move(center, 16);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 8,
          bottom: 8,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: _about,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Text(
                  '© OpenStreetMap contributors',
                  style: TextStyle(fontSize: 10),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _zoom(double step) => _controller.move(
    _controller.camera.center,
    (_controller.camera.zoom + step).clamp(_testTiles ? 2 : 8, 19),
  );
  String _time(DateTime value) {
    final d = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('คัดลอกพิกัดแล้ว')));
  }

  Future<void> _about() async {
    final license = await rootBundle.loadString(
      '${BundledPathumMap.folder}/ODbL-1.0.txt',
    );
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('แผนที่ปทุมธานีออฟไลน์'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ข้อมูลถนนจริงจาก OpenStreetMap contributors ผ่าน Geofabrik Shortbread วันที่ 19/10/2026\n'
                'ครอบคลุมกรอบจังหวัดปทุมธานีและพื้นที่ขอบใกล้เคียง ติดตั้ง 783 ไทล์ (~8.7 MB) ซูมข้อมูลระดับ 8–14 และขยายดูได้ถึง 19\n'
                'GPS ไม่ต้องใช้อินเทอร์เน็ต การหาพิกัดครั้งแรกอาจใช้เวลา ควรอยู่ในที่โล่ง\n'
                'แผนที่นี้แสดงถนนและพิกัด ไม่มีการคำนวณเส้นทางเลี้ยวต่อเลี้ยว\n'
                '© OpenStreetMap contributors · https://www.openstreetmap.org/copyright\n'
                'ฐานข้อมูลภายใต้ ODbL 1.0 · ฟอนต์ Noto Sans Thai ภายใต้ SIL OFL 1.1',
              ),
              const SizedBox(height: 12),
              SelectableText(license, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }
}
