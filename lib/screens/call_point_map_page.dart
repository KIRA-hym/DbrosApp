import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'
    if (dart.library.html) '../utils/maps_web_stub.dart' hide Cluster, ClusterManager;
import 'package:google_maps_cluster_manager_2/google_maps_cluster_manager_2.dart';
import 'package:geocoding/geocoding.dart';

import '../services/db_helper.dart';
import '../utils/call_map_placemark_title.dart';
import '../utils/marker_utils.dart';

class CallPointData with ClusterItem {
  final Map<String, dynamic> data;
  final LatLng position;

  CallPointData({required this.data, required this.position});

  @override
  LatLng get location => position;
}

enum MapFilterMode { all, radar, reference }

class CallPointMapPage extends StatefulWidget {
  const CallPointMapPage({super.key});

  @override
  State<CallPointMapPage> createState() => _CallPointMapPageState();
}

class _CallPointMapPageState extends State<CallPointMapPage> {
  late ClusterManager _manager;
  final Completer<GoogleMapController> _controller = Completer();
  Set<Marker> _markers = {};
  Position? _currentPosition;
  bool _loading = true;
  bool _permissionGranted = false;
  String _areaTitle = '';
  String _areaSubline = '';

  MapFilterMode _currentMode = MapFilterMode.all;
  List<CallPointData> _allPoints = [];

  // 캐싱된 마커 비트맵
  BitmapDescriptor? _logIconMine;
  BitmapDescriptor? _logIconOther;
  BitmapDescriptor? _refIcon;
  final Map<String, BitmapDescriptor> _clusterIcons = {};

  /// 마커 식별이 가능한 근접 줌 (전국 bounds 맞춤 대신 현재 위치 중심).
  static const double _localDetailZoom = 16.0;

  @override
  void initState() {
    super.initState();
    _manager = _initClusterManager();
    _initMap();
  }

  ClusterManager _initClusterManager() {
    return ClusterManager<CallPointData>(
      [],
      _updateMarkers,
      markerBuilder: _markerBuilder,
      stopClusteringZoom: 13.5,
    );
  }

  void _updateMarkers(Set<Marker> markers) {
    if (mounted) {
      setState(() {
        _markers = markers;
      });
    }
  }

  Future<void> _precacheIcons() async {
    _logIconMine ??= await MarkerUtils.createDataMarkerBitmap(
      size: 80,
      style: MarkerDataStyle.solid,
      color: const Color(0xFF10B981), // 녹색
    );
    _logIconOther ??= await MarkerUtils.createDataMarkerBitmap(
      size: 80,
      style: MarkerDataStyle.hollow,
      color: const Color(0xFF3B82F6), // 파란색
    );
    _refIcon ??= await MarkerUtils.createDataMarkerBitmap(
      size: 120,
      style: MarkerDataStyle.hotspot,
      color: const Color(0xFFF59E0B), // 주황색
    );
  }

  Future<void> _initMap() async {
    try {
      await _precacheIcons();
      _permissionGranted = await _handleLocationPermission();
      
      // 항상 DB 데이터 먼저 로드하여 마커를 표시할 수 있게 함
      await _loadData();

      if (_permissionGranted) {
        Position? pos;
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 10),
            ),
          );
        } catch (_) {
          try {
            pos = await Geolocator.getLastKnownPosition();
          } catch (_) {}
        }

        if (pos != null) {
          setState(() {
            _currentPosition = pos;
          });
          await _reverseGeocode(pos);
          await _focusOnCurrentLocation();
        }
      }
    } catch (e) {
      debugPrint('위치 가져오기 오류: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _reverseGeocode(Position pos) async {
    try {
      await setLocaleIdentifier('ko_KR');
      List<Placemark> placemarks = await placemarkFromCoordinates(
        pos.latitude, 
        pos.longitude,
      );
      if (placemarks.isNotEmpty) {
        final (line1, dong) = callMapTitlesFromPlacemark(placemarks.first);
        setState(() {
          _areaTitle = line1;
          _areaSubline = dong;
        });
      }
    } catch (e) {
      debugPrint('역지오코딩 오류: $e');
    }
  }

  Future<bool> _handleLocationPermission() async {
    if (kIsWeb) return true;
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  Future<void> _loadData() async {
    final db = await DriveLogDatabase.instance.database;
    final List<Map<String, dynamic>> rows = await db.query(
      'call_points',
      orderBy: 'created_at DESC',
      limit: 500,
    );

    List<CallPointData> points = [];
    for (var row in rows) {
      final lat = row['start_lat'] as num?;
      final lng = row['start_lng'] as num?;
      if (lat != null && lng != null) {
        points.add(CallPointData(
          data: row,
          position: LatLng(lat.toDouble(), lng.toDouble()),
        ));
      }
    }

    _allPoints = points;
    _applyFilter();
    await _focusOnCurrentLocation();
  }

  Future<void> _focusOnCurrentLocation() async {
    if (kIsWeb || _currentPosition == null || !_controller.isCompleted) return;
    try {
      final controller = await _controller.future;
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          _localDetailZoom,
        ),
      );
      _manager.updateMap();
    } catch (e) {
      debugPrint('현재 위치 카메라 이동 오류: $e');
    }
  }

  void _applyFilter() {
    final List<CallPointData> filtered;
    switch (_currentMode) {
      case MapFilterMode.all:
        filtered = List<CallPointData>.from(_allPoints);
        break;
      case MapFilterMode.radar:
        filtered = _allPoints.where((p) => p.data['type'] == 'log').toList();
        break;
      case MapFilterMode.reference:
        filtered = _allPoints.where((p) => p.data['type'] == 'reference').toList();
        break;
    }
    _manager.setItems(filtered);
  }

  void _onFilterTap(MapFilterMode mode) {
    setState(() {
      if (_currentMode == mode) {
        _currentMode = MapFilterMode.all;
      } else {
        _currentMode = mode;
      }
    });
    _applyFilter();
  }

  /// 운행시간 기준 낮(09~18) / 밤(18~09) — 일지 말풍선 제목 좌측.
  String _dayNightLeadingIcon(String? driveTime) {
    final t = driveTime?.trim() ?? '';
    if (t.isEmpty) return '';
    try {
      final hour = int.parse(t.split(':').first);
      if (hour >= 9 && hour < 18) return '🌞 ';
      return '🌙 ';
    } catch (_) {
      return '';
    }
  }

  String _referenceDisplayLocation(String startLoc) {
    if (startLoc.contains('(') && startLoc.contains(')')) {
      final match = RegExp(r'\((.*?)\)').firstMatch(startLoc);
      if (match != null) {
        return match.group(1)?.trim() ?? startLoc;
      }
    }
    return startLoc;
  }

  /// 마커 탭 시 Google Maps 기본 말풍선(마커 바로 아래).
  InfoWindow _infoWindowForCluster(Cluster<CallPointData> cluster) {
    if (!cluster.isMultiple) {
      return _infoWindowForPoint(cluster.items.first);
    }
    final first = cluster.items.first;
    final base = _infoWindowForPoint(first);
    final extra = cluster.count - 1;
    if (extra <= 0) return base;
    return InfoWindow(
      title: base.title,
      snippet: '${base.snippet ?? ''} · 외 $extra건',
    );
  }

  InfoWindow _infoWindowForPoint(CallPointData point) {
    final data = point.data;
    if (data['type'] == 'reference') {
      final loc = _referenceDisplayLocation(data['start_location']?.toString() ?? '');
      final name = loc.isNotEmpty ? loc : '콜포인트';
      return InfoWindow(
        title: name,
        snippet: '콜포인트',
      );
    }

    final driveTime = data['drive_time']?.toString().trim() ?? '';
    final dayNight = _dayNightLeadingIcon(driveTime.isNotEmpty ? driveTime : null);
    final program = data['program']?.toString().trim() ?? '';
    final startLoc = data['start_location']?.toString().trim() ?? '';
    final endLoc = data['end_location']?.toString().trim() ?? '';
    final timeLine = driveTime.isNotEmpty ? driveTime : '—';
    final programLine = program.isNotEmpty ? program : '—';
    final routeLine = startLoc.isNotEmpty || endLoc.isNotEmpty
        ? '${startLoc.isNotEmpty ? startLoc : '—'} → ${endLoc.isNotEmpty ? endLoc : '—'}'
        : '출발·도착 정보 없음';
    return InfoWindow(
      title: '$dayNight$timeLine · $programLine',
      snippet: routeLine,
    );
  }

  Future<void> _onMarkerTap(Cluster<CallPointData> cluster) async {
    if (!_controller.isCompleted) return;
    try {
      final controller = await _controller.future;
      if (cluster.isMultiple) {
        final zoom = await controller.getZoomLevel();
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            cluster.location,
            (zoom + 1.5).clamp(_localDetailZoom, 20.0),
          ),
        );
        _manager.updateMap();
        return;
      }
      await controller.showMarkerInfoWindow(MarkerId(cluster.getId()));
    } catch (e) {
      debugPrint('마커 InfoWindow 표시 오류: $e');
    }
  }

  Future<Marker> _markerBuilder(Cluster<CallPointData> cluster) async {
    Color color = Colors.red;
    final infoWindow = _infoWindowForCluster(cluster);
    final markerId = MarkerId(cluster.getId());

    if (!cluster.isMultiple) {
      final data = cluster.items.first.data;
      BitmapDescriptor icon;
      if (data['type'] == 'log') {
        if (data['is_mine'] == 1) {
          icon = _logIconMine!;
        } else {
          icon = _logIconOther!;
        }
      } else {
        icon = _refIcon!;
      }
      return Marker(
        markerId: markerId,
        position: cluster.location,
        infoWindow: infoWindow,
        onTap: () => _onMarkerTap(cluster),
        icon: icon,
      );
    } else {
      if (_currentMode == MapFilterMode.reference) {
        color = Colors.purple;
      } else {
        color = Theme.of(context).primaryColor;
      }
      final cacheKey = '${cluster.count}_${color.value}';
      if (!_clusterIcons.containsKey(cacheKey)) {
        _clusterIcons[cacheKey] = await _getMarkerBitmap(100, text: cluster.count.toString(), color: color);
      }
      return Marker(
        markerId: markerId,
        position: cluster.location,
        infoWindow: infoWindow,
        onTap: () => _onMarkerTap(cluster),
        icon: _clusterIcons[cacheKey]!,
      );
    }
  }

  Future<BitmapDescriptor> _getMarkerBitmap(int size, {String? text, Color color = Colors.red, bool isStar = false, bool isHeart = false}) async {
    final PictureRecorder pictureRecorder = PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final Paint paint = Paint()..color = color;

    if (text != null) {
      canvas.drawCircle(Offset(size / 2, size / 2), size / 2.0, paint);
      TextPainter painter = TextPainter(textDirection: TextDirection.ltr);
      painter.text = TextSpan(
        text: text,
        style: TextStyle(fontSize: size / 2.5, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontWeight: FontWeight.bold),
      );
      painter.layout();
      painter.paint(canvas, Offset(size / 2 - painter.width / 2, size / 2 - painter.height / 2));
    } else {
      if (isStar) {
        _drawStar(canvas, Offset(size / 2, size / 2), size / 2.0, paint);
      } else if (isHeart) {
        _drawHeart(canvas, size.toDouble(), paint);
      } else {
        canvas.drawCircle(Offset(size / 2, size / 2), size / 2.0, paint);
      }
    }

    final img = await pictureRecorder.endRecording().toImage(size, size);
    final data = await img.toByteData(format: ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    Path path = Path();
    int points = 5;
    double angle = (math.pi * 2) / points;
    for (int i = 0; i < points * 2; i++) {
      double r = (i % 2 == 0) ? radius : radius / 2;
      double theta = i * angle / 2 - math.pi / 2;
      double x = center.dx + r * math.cos(theta);
      double y = center.dy + r * math.sin(theta);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawHeart(Canvas canvas, double size, Paint paint) {
    Path path = Path();
    path.moveTo(size / 2, size / 4);
    path.cubicTo(size * 5 / 8, 0, size, 0, size, size * 3 / 8);
    path.cubicTo(size, size * 5 / 8, size / 2, size * 7 / 8, size / 2, size * 7 / 8);
    path.cubicTo(size / 2, size * 7 / 8, 0, size * 5 / 8, 0, size * 3 / 8);
    path.cubicTo(0, 0, size * 3 / 8, 0, size / 2, size / 4);
    canvas.drawPath(path, paint);
  }

  Widget _buildAppBarTitle() {
    // 첫 번째 줄: 지역명 + 동/읍/면 합쳐서 표시 (예: "성남시 정자동", "서초구 방배동")
    final dongSuffix = _areaSubline.isNotEmpty ? ' $_areaSubline' : '';
    final primary = _areaTitle.isNotEmpty ? '$_areaTitle$dongSuffix' : '주변';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on, color: Color(0xFFFF5252), size: 16),
            SizedBox(width: 4),
            Text(
              primary,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        Text(
          '주변 콜맵',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).primaryColor.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: 56,
        title: _buildAppBarTitle(),
        titleSpacing: 16,
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: Color(0xFFFFC700)),
            )
          : _buildMap(),
    );
  }

  Widget _buildFilterTabs() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _tabButton('콜레이더', MapFilterMode.radar),
        _tabButton('콜포인트', MapFilterMode.reference),
        SizedBox(width: 8),
      ],
    );
  }

  Widget _tabButton(String text, MapFilterMode mode) {
    final isSelected = _currentMode == mode;
    return GestureDetector(
      onTap: () => _onFilterTap(mode),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).primaryColor),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? Colors.black : Theme.of(context).primaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    if (kIsWeb) {
      return Center(
        child: Text(
          '웹 환경에서는 지도를 지원하지 않습니다.',
          style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withOpacity(0.7)),
        ),
      );
    }

    final initialPos = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(37.5665, 126.9780); // 서울시청 폴백
    // viewPadding은 SafeArea/Scaffold 에 의해 소비되지 않는 실제 시스템 인셋 값
    final navBarHeight = MediaQuery.viewPaddingOf(context).bottom;

    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: navBarHeight, // OS 네비게이션바 위까지만 지도 렌더링
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: initialPos,
              zoom: _localDetailZoom,
            ),
            padding: EdgeInsets.only(bottom: 8), // 지도 내부 컨트롤 여백
            onMapCreated: (GoogleMapController controller) async {
              if (!_controller.isCompleted) {
                _controller.complete(controller);
              }
              await _manager.setMapId(controller.mapId);
              await _focusOnCurrentLocation();
            },
            onCameraMove: _manager.onCameraMove,
            onCameraIdle: _manager.updateMap,
            markers: _markers,
            myLocationEnabled: _permissionGranted,
            myLocationButtonEnabled: _permissionGranted,
            compassEnabled: true,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
          ),
        ),
        _buildLegend(),
      ],
    );
  }

  Widget _buildLegend() {
    if (_currentMode == MapFilterMode.reference) return const SizedBox.shrink();

    return Positioned(
      top: 16,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _legendItem(const Color(0xFF10B981), '내 좌표', MarkerDataStyle.solid),
            SizedBox(height: 4),
            _legendItem(const Color(0xFF3B82F6), '공유된 좌표', MarkerDataStyle.hollow),
            if (_currentMode == MapFilterMode.all) ...[
              SizedBox(height: 4),
              _legendItem(const Color(0xFFF59E0B), '콜포인트', MarkerDataStyle.hotspot),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String text, MarkerDataStyle style) {
    Widget iconWidget;
    switch (style) {
      case MarkerDataStyle.solid:
        iconWidget = Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black87, width: 1.5),
          ),
        );
        break;
      case MarkerDataStyle.hollow:
        iconWidget = Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
        );
        break;
      case MarkerDataStyle.hotspot:
        iconWidget = Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color.withOpacity(0.9), color.withOpacity(0.1), Colors.transparent],
              stops: const [0.0, 0.7, 1.0],
            ),
          ),
          child: Center(
            child: Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        iconWidget,
        SizedBox(width: 6),
        Text(text, style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: 12)),
      ],
    );
  }
}
