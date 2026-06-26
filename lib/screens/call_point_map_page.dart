import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:intl/intl.dart' hide TextDirection;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'
    if (dart.library.html) '../utils/maps_web_stub.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/db_helper.dart';
import '../services/google_sheets_share_service.dart';
import '../utils/call_map_placemark_title.dart';
import '../utils/marker_utils.dart';

class CallPointData {
  final Map<String, dynamic> data;
  final LatLng position;

  CallPointData({required this.data, required this.position});
}

enum MapFilterMode { all, radar, reference }

class CallPointMapPage extends StatefulWidget {
  const CallPointMapPage({super.key});

  @override
  State<CallPointMapPage> createState() => _CallPointMapPageState();
}

class _CallPointMapPageState extends State<CallPointMapPage> {
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
  BitmapDescriptor? _restroomIcon;
  BitmapDescriptor? _shuttleIcon;
  final Map<String, BitmapDescriptor> _clusterIcons = {};

  /// 마커 식별이 가능한 근접 줌 (전국 bounds 맞춤 대신 현재 위치 중심).
  static const double _localDetailZoom = 16.0;

  @override
  void initState() {
    super.initState();
    _initMap();
  }

  Future<void> _precacheIcons() async {
    // 단순 동그라미 형태로 되돌리고, 요구사항(별모양 확대, 마커 테두리 검정색 적용)
    _logIconMine ??= await MarkerUtils.createCustomMarkerBitmap('❤', bgColor: const Color(0xFFEC4899), size: 65, borderColor: Colors.black, dy: 1.0);
    _logIconOther ??= await MarkerUtils.createCustomMarkerBitmap('@', bgColor: const Color(0xFF3B82F6), size: 65, borderColor: Colors.black, dy: 0.5);
    _refIcon ??= await MarkerUtils.createCustomMarkerBitmap('★', bgColor: const Color(0xFFFBBF24), size: 65, borderColor: Colors.black, textScale: 1.3, dy: -2.0);
    _restroomIcon ??= await MarkerUtils.createCustomMarkerBitmap('🚻', bgColor: Colors.white, textColor: Colors.black87, size: 65, borderColor: Colors.black, dy: 0.0);
    _shuttleIcon ??= await MarkerUtils.createCustomMarkerBitmap('🚌', bgColor: Colors.white, textColor: Colors.black87, size: 65, borderColor: Colors.black, dy: 0.0);
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
      limit: 20000,
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
        filtered = _allPoints.where((p) => p.data['type'] == 'log' || p.data['type'] == 'shared').toList();
        break;
      case MapFilterMode.reference:
        filtered = _allPoints.where((p) => p.data['type'] == 'reference' || p.data['type'] == 'restroom' || p.data['type'] == 'shuttle').toList();
        break;
    }
    
    final newMarkers = <Marker>{};
    for (final point in filtered) {
      newMarkers.add(_buildMarker(point));
    }
    
    if (mounted) {
      setState(() {
        _markers = newMarkers;
      });
    }
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

    final createdAtStr = data['created_at']?.toString().trim() ?? '';
    String displayDateTime = '';
    if (createdAtStr.length >= 16) {
      displayDateTime = createdAtStr.substring(0, 16).replaceAll('T', ' ');
    } else {
      displayDateTime = createdAtStr.isNotEmpty ? createdAtStr.replaceAll('T', ' ') : '시간 정보 없음';
    }

    final program = data['program']?.toString().trim() ?? '';
    final grossFareRaw = data['gross_fare'];
    final int grossFare = (grossFareRaw is int) ? grossFareRaw : int.tryParse(grossFareRaw?.toString() ?? '0') ?? 0;
    
    String programLine = '';
    if (program.isNotEmpty) {
      if (grossFare > 0) {
        programLine = ' · $program ${NumberFormat('#,###').format(grossFare)}';
      } else {
        programLine = ' · $program';
      }
    } else if (grossFare > 0) {
      programLine = ' · ${NumberFormat('#,###').format(grossFare)}';
    }
    
    final startLoc = data['start_location']?.toString().trim() ?? '';
    final endLoc = data['end_location']?.toString().trim() ?? '';
    final routeLine = startLoc.isNotEmpty || endLoc.isNotEmpty
        ? '${startLoc.isNotEmpty ? startLoc : '—'} → ${endLoc.isNotEmpty ? endLoc : '—'}'
        : '출발·도착 정보 없음';
        
    return InfoWindow(
      title: '$displayDateTime$programLine',
      snippet: routeLine,
    );
  }

  Future<void> _onMarkerTap(CallPointData point) async {
    if (!_controller.isCompleted) return;
    try {
      final controller = await _controller.future;
      await controller.showMarkerInfoWindow(MarkerId(point.data['id'].toString()));
    } catch (e) {
      debugPrint('마커 InfoWindow 표시 오류: $e');
    }
  }

  Marker _buildMarker(CallPointData point) {
    final infoWindow = _infoWindowForPoint(point);
    final markerId = MarkerId(point.data['id'].toString());
    final data = point.data;
    BitmapDescriptor icon;
    if (data['type'] == 'log' || data['type'] == 'shared') {
      if (data['is_mine'] == 1 || data['type'] == 'log') {
        // Note: In older code 'log' might mean mine. Let's explicitly check is_mine.
        if (data['is_mine'] == 1) {
          icon = _logIconMine!;
        } else {
          icon = _logIconOther!;
        }
      } else {
        icon = _logIconOther!;
      }
    } else if (data['type'] == 'restroom') {
      icon = _restroomIcon!;
    } else if (data['type'] == 'shuttle') {
      icon = _shuttleIcon!;
    } else {
      icon = _refIcon!;
    }

    return Marker(
      markerId: markerId,
      position: point.position,
      infoWindow: infoWindow,
      onTap: () => _onMarkerTap(point),
      icon: icon,
    );
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
        actions: [
          IconButton(
            icon: Icon(Icons.sync, color: Theme.of(context).primaryColor),
            tooltip: '주변콜맵 업데이트',
            onPressed: () async {
              // 쿨타임 체크 (5분)
              final prefs = await SharedPreferences.getInstance();
              final lastSync = prefs.getInt('lastGoogleSheetSync') ?? 0;
              final now = DateTime.now().millisecondsSinceEpoch;
              if (now - lastSync < 5 * 60 * 1000) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('업데이트는 5분마다 가능합니다. 잠시 후 다시 시도해주세요.')),
                );
                return;
              }

              // 로딩 표시
              if (!mounted) return;
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(child: CircularProgressIndicator()),
              );

              final success = await GoogleSheetsShareService.fetchSharedCoordinates();

              if (!mounted) return;
              Navigator.pop(context); // Hide loading

              if (success) {
                await prefs.setInt('lastGoogleSheetSync', now);
                await _loadData(); // 마커 다시 불러오기
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('주변콜맵이 최신 정보로 업데이트되었습니다!')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('업데이트에 실패했습니다. 네트워크를 확인해주세요.')),
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
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
              await _focusOnCurrentLocation();
            },
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
            _legendItem(const Color(0xFFEC4899), '내 좌표', '❤', borderColor: Colors.black, dy: 0.5),
            SizedBox(height: 4),
            _legendItem(const Color(0xFF3B82F6), '공유좌표', '@', borderColor: Colors.black, dy: 0.5),
            if (_currentMode == MapFilterMode.all) ...[
              SizedBox(height: 4),
              _legendItem(const Color(0xFFFBBF24), '콜포인트', '★', borderColor: Colors.black, textScale: 1.3, dy: -1.0),
              SizedBox(height: 4),
              _legendItem(Colors.white, '화장실', '🚻', textColor: Colors.black87, borderColor: Colors.black),
              SizedBox(height: 4),
              _legendItem(Colors.white, '셔틀', '🚌', textColor: Colors.black87, borderColor: Colors.black),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color bgColor, String text, String symbol, {Color textColor = Colors.white, double textScale = 1.0, Color borderColor = Colors.transparent, double dy = 0.0}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor == Colors.transparent ? Colors.black26 : borderColor, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Text(
              symbol,
              style: TextStyle(
                color: textColor,
                fontSize: 10 * textScale,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: 12)),
      ],
    );
  }
}
