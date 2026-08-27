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


import '../services/db_helper.dart';

import '../utils/call_map_placemark_title.dart';
import '../utils/marker_utils.dart';

import '../services/settings_service.dart';

class CallPointData {
  final Map<String, dynamic> data;
  final LatLng position;

  CallPointData({required this.data, required this.position});
}

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

  List<String> _visibleTypes = [];
  List<CallPointData> _allPoints = [];

  // 캐싱된 마커 비트맵
  BitmapDescriptor? _logIconMine;
  BitmapDescriptor? _logIconOther;
  BitmapDescriptor? _refIcon;
  BitmapDescriptor? _restroomIcon;
  BitmapDescriptor? _shuttleIcon;
  BitmapDescriptor? _logIconMineSelected;
  BitmapDescriptor? _logIconOtherSelected;
  BitmapDescriptor? _refIconSelected;
  BitmapDescriptor? _restroomIconSelected;
  BitmapDescriptor? _shuttleIconSelected;
  
  String? _selectedLocKey;
  final Map<String, List<CallPointData>> _groupedPoints = {};
  final Map<String, BitmapDescriptor> _clusterIcons = {};

  /// 마커 식별이 가능한 근접 줌 (전국 bounds 맞춤 대신 현재 위치 중심).
  static const double _localDetailZoom = 16.0;

  @override
  void initState() {
    super.initState();
    _visibleTypes = SettingsService.mapVisibleTypes;
    _initMap();
  }

  Future<void> _precacheIcons() async {
    // 단순 동그라미 형태를 내돌리고, 요구사항(별모양 하트, 마커 테두리 검정색 적용)
    _logIconMine ??= await MarkerUtils.createCustomMarkerBitmap('❤', bgColor: const Color(0xFFEC4899), size: 65, borderColor: Colors.black, dy: 1.0);
    _logIconOther ??= await MarkerUtils.createCustomMarkerBitmap('@', bgColor: const Color(0xFF3B82F6), size: 65, borderColor: Colors.black, dy: 0.5);
    _refIcon ??= await MarkerUtils.createCustomMarkerBitmap('★', bgColor: const Color(0xFFFBBF24), size: 65, borderColor: Colors.black, textScale: 1.3, dy: -2.0);
    _restroomIcon ??= await MarkerUtils.createCustomMarkerBitmap('🚻', bgColor: Colors.white, textColor: Colors.black87, size: 65, borderColor: Colors.black, dy: 0.0);
    _shuttleIcon ??= await MarkerUtils.createCustomMarkerBitmap('🚌', bgColor: Colors.white, textColor: Colors.black87, size: 65, borderColor: Colors.black, dy: 0.0);
    
    _logIconMineSelected ??= await MarkerUtils.createCustomMarkerBitmap('❤', bgColor: const Color(0xFFEC4899), size: 85, borderColor: Colors.white, dy: 1.0);
    _logIconOtherSelected ??= await MarkerUtils.createCustomMarkerBitmap('@', bgColor: const Color(0xFF3B82F6), size: 85, borderColor: Colors.white, dy: 0.5);
    _refIconSelected ??= await MarkerUtils.createCustomMarkerBitmap('★', bgColor: const Color(0xFFFBBF24), size: 85, borderColor: Colors.white, textScale: 1.3, dy: -2.0);
    _restroomIconSelected ??= await MarkerUtils.createCustomMarkerBitmap('🚻', bgColor: Colors.white, textColor: Colors.black87, size: 85, borderColor: Colors.yellowAccent, dy: 0.0);
    _shuttleIconSelected ??= await MarkerUtils.createCustomMarkerBitmap('🚌', bgColor: Colors.white, textColor: Colors.black87, size: 85, borderColor: Colors.yellowAccent, dy: 0.0);
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
    final List<CallPointData> filtered = _allPoints.where((p) {
      final type = p.data['type'];
      final isMine = p.data['is_mine'] == 1;
      
      if (type == 'log' && isMine) return _visibleTypes.contains('log_mine');
      if (type == 'log' && !isMine) return _visibleTypes.contains('log_other');
      if (type == 'shared') return _visibleTypes.contains('shared');
      if (type == 'reference') return _visibleTypes.contains('reference');
      if (type == 'restroom') return _visibleTypes.contains('restroom');
      if (type == 'shuttle') return _visibleTypes.contains('shuttle');
      return false;
    }).toList();
    
    final newMarkers = <Marker>{};
    _groupedPoints.clear();
    final locationCounts = <String, int>{};
    
    int index = 0;
    for (final point in filtered) {
      final locKey = '${point.position.latitude.toStringAsFixed(5)},${point.position.longitude.toStringAsFixed(5)}';
      if (!_groupedPoints.containsKey(locKey)) { _groupedPoints[locKey] = []; }
      _groupedPoints[locKey]!.add(point);
      final overlapCount = locationCounts[locKey] ?? 0;
      locationCounts[locKey] = overlapCount + 1;
      
      double jitterLat = point.position.latitude;
      double jitterLng = point.position.longitude;
      
      // 완전히 같은 위치에 있는 마커들이 서로를 가리지 않도록 약간 분산 (jitter)
      if (overlapCount > 0) {
        // overlapCount에 따라 대각선으로 약 1.5~2미터 간격 벌림
        jitterLat += (overlapCount * 0.000015);
        jitterLng += (overlapCount * 0.000015);
      }
      
      final adjustedPosition = LatLng(jitterLat, jitterLng);
      newMarkers.add(_buildMarker(point, adjustedPosition, index, locKey));
      index++;
    }
    
    if (mounted) {
      setState(() {
        _markers = newMarkers;
      });
    }
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget _buildCheckbox(String key, String title, Color color) {
              final isSelected = _visibleTypes.contains(key);
              return CheckboxListTile(
                title: Text(title, style: const TextStyle(fontSize: 15)),
                activeColor: color,
                value: isSelected,
                onChanged: (bool? value) async {
                  if (value == true) {
                    _visibleTypes.add(key);
                  } else {
                    _visibleTypes.remove(key);
                  }
                  await SettingsService.setMapVisibleTypes(_visibleTypes);
                  setModalState(() {});
                  _applyFilter();
                },
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      child: Text('지도 마커 표시 설정', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    const Divider(),
                    _buildCheckbox('log_mine', '내 일지 기록', const Color(0xFFEC4899)),
                    _buildCheckbox('shared', '주변 공유/타인 일지', const Color(0xFF3B82F6)),
                    _buildCheckbox('reference', '대기/콜포인트', const Color(0xFFFBBF24)),
                    _buildCheckbox('restroom', '화장실', Colors.grey),
                    _buildCheckbox('shuttle', '셔틀', Colors.grey),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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



  void _onMarkerTap(String locKey) {
    if (!mounted) return;
    setState(() {
      _selectedLocKey = locKey;
      _applyFilter();
    });
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildBottomSheet(locKey),
    ).whenComplete(() {
      if (mounted) {
        setState(() {
          _selectedLocKey = null;
          _applyFilter();
        });
      }
    });
  }

  Widget _buildBottomSheet(String locKey) {
    final points = _groupedPoints[locKey] ?? [];
    
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E2025),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(top: 16, bottom: 40, left: 20, right: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 5,
            decoration: BoxDecoration(color: const Color(0xFF4A4D55), borderRadius: BorderRadius.circular(3)),
            margin: const EdgeInsets.only(bottom: 20),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: points.length,
              separatorBuilder: (c, i) => const SizedBox(height: 16),
              itemBuilder: (c, i) => _buildBottomSheetItem(points[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSheetItem(CallPointData point) {
    final data = point.data;
    final type = data['type'];
    final isMine = data['is_mine'] == 1;
    
    String badgeText = '';
    Color badgeColor = Colors.grey;
    Color badgeBg = Colors.grey.withOpacity(0.2);
    
    if (type == 'log' || type == 'shared') {
      badgeText = isMine ? '내 기록' : '공유 콜';
      badgeColor = isMine ? const Color(0xFFEC4899) : const Color(0xFF3B82F6);
      badgeBg = badgeColor.withOpacity(0.2);
    } else if (type == 'reference') {
      badgeText = '대기 콜포인트';
      badgeColor = const Color(0xFFFBBF24);
      badgeBg = badgeColor.withOpacity(0.2);
    } else if (type == 'restroom') {
      badgeText = '화장실';
      badgeColor = Colors.white;
      badgeBg = Colors.white24;
    } else if (type == 'shuttle') {
      badgeText = '셔틀';
      badgeColor = Colors.white;
      badgeBg = Colors.white24;
    }

    final createdAtStr = data['created_at']?.toString().trim() ?? '';
    String displayDateTime = '';
    if (createdAtStr.length >= 16) {
      displayDateTime = createdAtStr.substring(0, 16).replaceAll('T', ' ');
    } else {
      displayDateTime = createdAtStr.isNotEmpty ? createdAtStr.replaceAll('T', ' ') : '';
    }

    final program = data['program']?.toString().trim() ?? '';
    final grossFareRaw = data['gross_fare'];
    final int grossFare = (grossFareRaw is int) ? grossFareRaw : int.tryParse(grossFareRaw?.toString() ?? '0') ?? 0;
    
    final startLoc = data['start_location']?.toString().trim() ?? '';
    final endLoc = data['end_location']?.toString().trim() ?? '';
    
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF282B33),
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: badgeColor, width: 5)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(4)),
                    child: Text(badgeText, style: TextStyle(color: badgeColor, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  Text(displayDateTime, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
                ],
              ),
              if (program.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF60A5FA).withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(program, style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 14, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  const SizedBox(height: 4),
                  Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF3B82F6), shape: BoxShape.circle)),
                  Container(width: 2, height: 24, color: const Color(0xFF4A4D55), margin: const EdgeInsets.symmetric(vertical: 4)),
                  Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(startLoc.isNotEmpty ? startLoc : '출발지 정보 없음', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: startLoc.isNotEmpty ? const Color(0xFFF3F4F6) : const Color(0xFF6B7280))),
                    const SizedBox(height: 16),
                    Text(endLoc.isNotEmpty ? endLoc : '도착지 정보 없음', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: endLoc.isNotEmpty ? const Color(0xFFF3F4F6) : const Color(0xFF6B7280))),
                  ],
                ),
              ),
            ],
          ),
          if (grossFare > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF4A4D55), style: BorderStyle.solid))),
              alignment: Alignment.centerRight,
              child: Text('${NumberFormat('#,###').format(grossFare)} 원', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFFBBF24))),
            ),
          ]
        ],
      ),
    );
  }

  Marker _buildMarker(CallPointData point, LatLng position, int index, String locKey) {
    final data = point.data;
    bool isSelected = _selectedLocKey == locKey;
    BitmapDescriptor icon;
    double zIndex = isSelected ? 100.0 : 0.0;
    
    if (data['type'] == 'log' || data['type'] == 'shared') {
      if (data['is_mine'] == 1 || data['type'] == 'log') {
        if (data['is_mine'] == 1) {
          icon = isSelected ? _logIconMineSelected! : _logIconMine!;
          if (!isSelected) zIndex = 5.0;
        } else {
          icon = isSelected ? _logIconOtherSelected! : _logIconOther!;
        }
      } else {
        icon = isSelected ? _logIconOtherSelected! : _logIconOther!;
      }
    } else if (data['type'] == 'restroom') {
      icon = isSelected ? _restroomIconSelected! : _restroomIcon!;
      if (!isSelected) zIndex = 10.0;
    } else if (data['type'] == 'shuttle') {
      icon = isSelected ? _shuttleIconSelected! : _shuttleIcon!;
      if (!isSelected) zIndex = 10.0;
    } else {
      icon = isSelected ? _refIconSelected! : _refIcon!;
    }

    return Marker(
      markerId: MarkerId('${data['id']}_$index'),
      position: position,
      onTap: () => _onMarkerTap(locKey),
      icon: icon,
      zIndex: zIndex,
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
            icon: Icon(Icons.layers, color: Theme.of(context).primaryColor),
            tooltip: '마커 표시 설정',
            onPressed: _showFilterBottomSheet,
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
            if (_visibleTypes.contains('log_mine'))
              _legendItem(const Color(0xFFEC4899), '내 좌표', '❤', borderColor: Colors.black, dy: 0.5),
            if (_visibleTypes.contains('shared')) ...[
              SizedBox(height: 4),
              _legendItem(const Color(0xFF3B82F6), '공유/타인좌표', '@', borderColor: Colors.black, dy: 0.5),
            ],
            if (_visibleTypes.contains('reference')) ...[
              SizedBox(height: 4),
              _legendItem(const Color(0xFFFBBF24), '콜포인트', '★', borderColor: Colors.black, textScale: 1.3, dy: -1.0),
            ],
            if (_visibleTypes.contains('restroom')) ...[
              SizedBox(height: 4),
              _legendItem(Colors.white, '화장실', '🚻', textColor: Colors.black87, borderColor: Colors.black),
            ],
            if (_visibleTypes.contains('shuttle')) ...[
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
