import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'
    if (dart.library.html) '../utils/maps_web_stub.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../services/call_point_analytics_service.dart';
import '../utils/responsive_layout.dart';

/// 프리미엄 전용 콜포인트맵 & 상권/단가 분석 화면.
///
/// - 소형폰(340dp)·큰 글꼴: 2×2 KPI 자동 전환, 필터 바 접기/펼치기, DraggableScrollableSheet
/// - 일반 스마트폰(360~599dp): 4열 KPI + 지도 + DraggableScrollableSheet (지도 크게/기본/목록 크게)
/// - 폴드 펼침·태블릿(>=600dp): 좌측 지도(56%) + 우측 고정 분석 패널(44%) 2열 분할
class PremiumCallPointMapPage extends StatefulWidget {
  const PremiumCallPointMapPage({super.key});

  @override
  State<PremiumCallPointMapPage> createState() =>
      _PremiumCallPointMapPageState();
}

class _PremiumCallPointMapPageState extends State<PremiumCallPointMapPage> {
  final Completer<GoogleMapController> _mapController = Completer();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  final TextEditingController _searchCon = TextEditingController();

  bool _loading = true;
  bool _refreshing = false;
  String? _errorMsg;
  String _updatedAtIso = '';
  bool _fromCache = false;

  Position? _userPos;
  bool _locationPermissionGranted = false;

  List<AnalyticsCallPoint> _allPoints = const [];
  CallPointAnalyticsResult? _result;

  // 인터랙티브 필터 상태
  CallTimeSlotFilter _timeSlot = CallTimeSlotFilter.all;
  int? _exactHour;
  CallFareFilter _fareFilter = CallFareFilter.all;
  String _platformFilter = 'all';
  CallRadiusFilter _radiusFilter = CallRadiusFilter.all;
  CallColorMode _colorMode = CallColorMode.fare;
  String? _selectedRegion;
  bool _sortRegionByFare = false;
  bool _filterCollapsed = false;
  int _sheetTabIndex = 0; // 0: 핫스팟 TOP, 1: 시간·플랫폼, 2: 콜 목록

  AnalyticsCallPoint? _selectedPoint;
  String? _selectedCoordKey;
  ScrollController? _activeSheetScrollController;
  Set<Marker> _markers = const {};

  static String _coordKeyOf(AnalyticsCallPoint pt) =>
      '${pt.lat.toStringAsFixed(4)}_${pt.lng.toStringAsFixed(4)}';

  void _scrollSheetToTop() {
    final ctrl = _activeSheetScrollController;
    if (ctrl != null && ctrl.hasClients && ctrl.offset > 0) {
      try {
        ctrl.jumpTo(0);
      } catch (_) {}
    }
  }
  LatLng _cameraTarget = const LatLng(37.5665, 126.9780);
  LatLngBounds? _visibleBounds;
  Timer? _cameraDebounce;

  static const int _maxMarkersPerViewport = 250;
  static final Map<String, BitmapDescriptor> _markerIconCache = {};

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _cameraDebounce?.cancel();
    _sheetController.dispose();
    _searchCon.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _precacheMarkerIcons();
    await _initLocationBestEffort();
    await _loadData(forceRefresh: false);
  }

  Future<void> _precacheMarkerIcons() async {
    if (kIsWeb || _markerIconCache.isNotEmpty) return;
    final specs = <String, (Color, Color, int)>{
      'fare_50k': (const Color(0xFFEF4444), const Color(0xFFFDE047), 44),
      'fare_30k': (const Color(0xFFF59E0B), Colors.white, 36),
      'fare_low': (const Color(0xFF3B82F6), Colors.white, 28),
      'plat_kakao': (const Color(0xFFEAB308), Colors.white, 34),
      'plat_logi': (const Color(0xFF22C55E), Colors.white, 34),
      'plat_col': (const Color(0xFFA855F7), Colors.white, 34),
      'plat_tmap': (const Color(0xFF3B82F6), Colors.white, 34),
      'plat_handle': (const Color(0xFFE5E7EB), const Color(0xFF111827), 34),
      'plat_other': (const Color(0xFF9CA3AF), Colors.white, 30),
      'selected': (const Color(0xFFFFC700), Colors.white, 52),
    };
    for (final entry in specs.entries) {
      final (fill, border, size) = entry.value;
      _markerIconCache[entry.key] = await _createCircleMarkerBitmap(
        size: size,
        fillColor: fill,
        borderColor: border,
        borderWidth: entry.key == 'fare_50k' || entry.key == 'selected'
            ? 4.0
            : 2.5,
      );
    }
  }

  Future<BitmapDescriptor> _createCircleMarkerBitmap({
    required int size,
    required Color fillColor,
    required Color borderColor,
    required double borderWidth,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final double r = size / 2.0;
    final center = Offset(r, r);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.38)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2.5);
    canvas.drawCircle(center, r - 2.0, shadowPaint);

    final fillPaint = Paint()
      ..color = fillColor.withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, r - borderWidth - 1.5, fillPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    canvas.drawCircle(center, r - borderWidth - 1.5, borderPaint);

    final img = await recorder.endRecording().toImage(size, size);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  Future<void> _initLocationBestEffort() async {
    if (kIsWeb) return;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      _locationPermissionGranted = true;
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        _userPos = last;
        _cameraTarget = LatLng(last.latitude, last.longitude);
        _radiusFilter = CallRadiusFilter.km3; // GPS 확보 시 기본 3km
      }
      // 정밀 위치는 백그라운드로 보강
      unawaited(_refreshPreciseLocation());
    } catch (_) {}
  }

  Future<void> _refreshPreciseLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
      if (!mounted) return;
      final hadPos = _userPos != null;
      _userPos = pos;
      if (!hadPos) {
        _cameraTarget = LatLng(pos.latitude, pos.longitude);
        _radiusFilter = CallRadiusFilter.km3; // GPS 확보 시 기본 3km
        _recompute();
        await _moveCamera(LatLng(pos.latitude, pos.longitude), zoom: 13.8);
      }
    } catch (_) {}
  }

  Future<void> _loadData({required bool forceRefresh}) async {
    if (mounted) {
      setState(() {
        if (forceRefresh) {
          _refreshing = true;
        } else {
          _loading = true;
        }
        _errorMsg = null;
      });
    }
    try {
      final dataset = await CallPointAnalyticsService.loadDataset(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      _allPoints = dataset.points;
      _updatedAtIso = dataset.updatedAtIso;
      _fromCache = dataset.fromCache;
      _recompute();
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _errorMsg = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _recompute() {
    final res = CallPointAnalyticsService.computeAnalytics(
      allPoints: _allPoints,
      timeSlot: _timeSlot,
      exactHour: _exactHour,
      fareFilter: _fareFilter,
      platformFilter: _platformFilter,
      radiusFilter: _radiusFilter,
      userLat: _userPos?.latitude,
      userLng: _userPos?.longitude,
      selectedRegion: _selectedRegion,
      searchQuery: _searchCon.text,
      sortRegionByFare: _sortRegionByFare,
    );
    _result = res;
    _rebuildMarkers();
  }

  void _rebuildMarkers() {
    if (kIsWeb || _result == null) return;
    final points = _result!.filteredPoints;
    final bounds = _visibleBounds;

    List<AnalyticsCallPoint> candidates;
    if (bounds != null) {
      final minLat =
          math.min(bounds.southwest.latitude, bounds.northeast.latitude);
      final maxLat =
          math.max(bounds.southwest.latitude, bounds.northeast.latitude);
      final minLng =
          math.min(bounds.southwest.longitude, bounds.northeast.longitude);
      final maxLng =
          math.max(bounds.southwest.longitude, bounds.northeast.longitude);
      final latM = math.max(0.015, (maxLat - minLat) * 0.25);
      final lngM = math.max(0.015, (maxLng - minLng) * 0.25);
      candidates = points
          .where((p) =>
              p.lat >= minLat - latM &&
              p.lat <= maxLat + latM &&
              p.lng >= minLng - lngM &&
              p.lng <= maxLng + lngM)
          .toList();
    } else {
      candidates = List<AnalyticsCallPoint>.from(points);
    }

    if (candidates.length > _maxMarkersPerViewport) {
      final cLat = _cameraTarget.latitude;
      final cLng = _cameraTarget.longitude;
      candidates.sort((a, b) {
        final da = (a.lat - cLat) * (a.lat - cLat) +
            (a.lng - cLng) * (a.lng - cLng);
        final db = (b.lat - cLat) * (b.lat - cLat) +
            (b.lng - cLng) * (b.lng - cLng);
        return da.compareTo(db);
      });
      candidates = candidates.sublist(0, _maxMarkersPerViewport);
    }

    final Set<Marker> built = {};
    for (int i = 0; i < candidates.length; i++) {
      final pt = candidates[i];
      final isSel = identical(_selectedPoint, pt) ||
          (_selectedCoordKey != null && _coordKeyOf(pt) == _selectedCoordKey);
      final icon = _iconForPoint(pt, isSel);
      final z = isSel
          ? 100.0
          : (pt.fare >= 50000
              ? 30.0
              : (pt.fare >= 30000 ? 15.0 : 5.0));
      built.add(
        Marker(
          markerId: MarkerId('cp_${pt.lat}_${pt.lng}_$i'),
          position: LatLng(pt.lat, pt.lng),
          icon: icon,
          zIndexInt: z.toInt(),
          onTap: () {
            final key = _coordKeyOf(pt);
            setState(() {
              _selectedPoint = pt;
              _selectedCoordKey = key;
              _sheetTabIndex = 2; // 📋 콜 목록 탭으로 자동 포커스
              _rebuildMarkers();
            });
            _scrollSheetToTop();
            if (_sheetController.isAttached && _sheetController.size < 0.36) {
              _animateSheetTo(0.44);
            }
          },
        ),
      );
    }

    if (mounted) {
      setState(() => _markers = built);
    }
  }

  BitmapDescriptor _iconForPoint(AnalyticsCallPoint pt, bool isSelected) {
    if (isSelected) {
      return _markerIconCache['selected'] ?? BitmapDescriptor.defaultMarker;
    }
    if (_colorMode == CallColorMode.fare) {
      if (pt.fare >= 50000) {
        return _markerIconCache['fare_50k'] ?? BitmapDescriptor.defaultMarker;
      }
      if (pt.fare >= 30000) {
        return _markerIconCache['fare_30k'] ?? BitmapDescriptor.defaultMarker;
      }
      return _markerIconCache['fare_low'] ?? BitmapDescriptor.defaultMarker;
    }
    final p = pt.programName;
    if (p.contains('카카오')) {
      return _markerIconCache['plat_kakao'] ?? BitmapDescriptor.defaultMarker;
    }
    if (p.contains('로지')) {
      return _markerIconCache['plat_logi'] ?? BitmapDescriptor.defaultMarker;
    }
    if (p.contains('콜마너')) {
      return _markerIconCache['plat_col'] ?? BitmapDescriptor.defaultMarker;
    }
    if (p.contains('티맵')) {
      return _markerIconCache['plat_tmap'] ?? BitmapDescriptor.defaultMarker;
    }
    if (p.contains('핸들')) {
      return _markerIconCache['plat_handle'] ?? BitmapDescriptor.defaultMarker;
    }
    return _markerIconCache['plat_other'] ?? BitmapDescriptor.defaultMarker;
  }

  Future<void> _moveCamera(LatLng target, {double zoom = 14.0}) async {
    if (kIsWeb || !_mapController.isCompleted) return;
    try {
      final ctrl = await _mapController.future;
      await ctrl.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
    } catch (_) {}
  }

  Future<void> _updateVisibleBounds() async {
    if (kIsWeb || !_mapController.isCompleted) return;
    try {
      final ctrl = await _mapController.future;
      final bounds = await ctrl
          .getVisibleRegion()
          .timeout(const Duration(milliseconds: 500));
      if ((bounds.northeast.latitude - bounds.southwest.latitude).abs() >
          0.0001) {
        _visibleBounds = bounds;
      }
    } catch (_) {}
    _rebuildMarkers();
  }

  void _cycleRadius() {
    if (_userPos == null && _radiusFilter == CallRadiusFilter.all) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('현재 위치를 확인할 수 없어 전체 기준으로 표시합니다. 위치 권한을 확인해 주세요.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() {
      _radiusFilter = _radiusFilter.next;
      _selectedPoint = null;
      _selectedCoordKey = null;
      _recompute();
    });
    if (_userPos != null) {
      final zoom = switch (_radiusFilter) {
        CallRadiusFilter.km3 => 13.8,
        CallRadiusFilter.km5 => 13.0,
        CallRadiusFilter.km10 => 12.0,
        CallRadiusFilter.all => 10.6,
      };
      _moveCamera(LatLng(_userPos!.latitude, _userPos!.longitude), zoom: zoom);
    }
  }

  void _resetFilters() {
    _searchCon.clear();
    setState(() {
      _timeSlot = CallTimeSlotFilter.all;
      _exactHour = null;
      _fareFilter = CallFareFilter.all;
      _platformFilter = 'all';
      _selectedRegion = null;
      _selectedPoint = null;
      _selectedCoordKey = null;
      _radiusFilter =
          _userPos != null ? CallRadiusFilter.km3 : CallRadiusFilter.all;
      _recompute();
    });
    if (_userPos != null) {
      _moveCamera(
        LatLng(_userPos!.latitude, _userPos!.longitude),
        zoom: 13.8,
      );
    }
  }

  bool get _hasActiveFilter =>
      _timeSlot != CallTimeSlotFilter.all ||
      _exactHour != null ||
      _fareFilter != CallFareFilter.all ||
      _platformFilter != 'all' ||
      _selectedRegion != null ||
      _selectedCoordKey != null ||
      _searchCon.text.trim().isNotEmpty;

  String _buildFilterSummaryText() {
    final tTxt = _exactHour != null
        ? '${_exactHour.toString().padLeft(2, '0')}시'
        : switch (_timeSlot) {
            CallTimeSlotFilter.all => '전체 시간',
            CallTimeSlotFilter.evening => '초저녁(18~21)',
            CallTimeSlotFilter.peak => '야간피크(21~01)',
            CallTimeSlotFilter.late => '심야(01~05)',
            CallTimeSlotFilter.day => '주간(05~18)',
          };
    final fTxt = switch (_fareFilter) {
      CallFareFilter.all => '전체 단가',
      CallFareFilter.over30k => '3만↑',
      CallFareFilter.over50k => '5만↑ 꿀콜',
    };
    final pTxt = _platformFilter == 'all' ? '전 플랫폼' : _platformFilter;
    final rTxt = _selectedRegion != null ? ' · $_selectedRegion' : '';
    return '$tTxt · $fTxt · $pTxt$rTxt';
  }

  void _animateSheetTo(double targetSize) {
    if (!_sheetController.isAttached) return;
    _sheetController.animateTo(
      targetSize,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final cardColor = Theme.of(context).cardTheme.color ?? const Color(0xFF1F222A);
    final primary = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        toolbarHeight: 52,
        backgroundColor: cardColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '콜포인트맵',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 6),
            MediaQuery.withClampedTextScaling(
              minScaleFactor: 0.9,
              maxScaleFactor: 1.15,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '프리미엄',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (_hasActiveFilter)
            TextButton(
              onPressed: _resetFilters,
              child: Text(
                '초기화',
                style: TextStyle(
                  color: primary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          IconButton(
            tooltip: '최신 데이터 갱신',
            onPressed: _refreshing ? null : () => _loadData(forceRefresh: true),
            icon: _refreshing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primary,
                    ),
                  )
                : Icon(Icons.refresh_rounded, color: primary),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: primary),
                    const SizedBox(height: 12),
                    const Text(
                      '전국 상권·단가 데이터를 불러오는 중...',
                      style: TextStyle(color: Color(0xFF9FA3AE), fontSize: 13),
                    ),
                  ],
                ),
              )
            : _errorMsg != null
                ? _buildErrorState()
                : _buildResponsiveContent(),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFFF5252),
              size: 44,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMsg ?? '데이터 로드 오류',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC700),
                foregroundColor: Colors.black,
              ),
              onPressed: () => _loadData(forceRefresh: true),
              child: const Text(
                '다시 시도',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsiveContent() {
    final res = _result!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide =
            constraints.maxWidth >= ResponsiveLayout.breakpoint;
        final double textScale =
            MediaQuery.textScalerOf(context).scale(14.0) / 14.0;
        final bool use2x2Kpi =
            constraints.maxWidth < 380 || textScale > 1.15;

        return Column(
          children: [
            _buildFilterBar(constraints.maxWidth),
            _buildKpiStrip(res, use2x2: use2x2Kpi),
            Expanded(
              child: isWide
                  ? Row(
                      children: [
                        Expanded(flex: 13, child: _buildMapArea()),
                        Container(
                          width: 1,
                          color: Theme.of(context).dividerColor,
                        ),
                        Expanded(
                          flex: 10,
                          child: _buildAnalyticsPanel(
                            res,
                            scrollController: null,
                            showGrabBar: false,
                            sheetViewportHeight: 0,
                          ),
                        ),
                      ],
                    )
                  : LayoutBuilder(
                      builder: (stackCtx, stackConstraints) {
                        final viewportH = stackConstraints.maxHeight;
                        return Stack(
                          children: [
                            Positioned.fill(child: _buildMapArea()),
                            DraggableScrollableSheet(
                              controller: _sheetController,
                              initialChildSize: 0.44,
                              minChildSize: 0.22,
                              maxChildSize: 0.86,
                              snap: true,
                              snapSizes: const [0.22, 0.44, 0.86],
                              builder: (ctx, scrollController) {
                                _activeSheetScrollController = scrollController;
                                return Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .scaffoldBackgroundColor,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(20),
                                    ),
                                    border: Border(
                                      top: BorderSide(
                                        color: Theme.of(context).dividerColor,
                                      ),
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black54,
                                        blurRadius: 14,
                                        offset: Offset(0, -4),
                                      ),
                                    ],
                                  ),
                                  child: _buildAnalyticsPanel(
                                    res,
                                    scrollController: scrollController,
                                    showGrabBar: true,
                                    sheetViewportHeight: viewportH,
                                  ),
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterBar(double maxWidth) {
    final cardColor = Theme.of(context).cardTheme.color ?? const Color(0xFF1F222A);
    final dividerColor = Theme.of(context).dividerColor;
    final primary = Theme.of(context).primaryColor;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(bottom: BorderSide(color: dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _buildFilterSummaryText(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD1D5DB),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () =>
                    setState(() => _filterCollapsed = !_filterCollapsed),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14171D),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: dividerColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _filterCollapsed ? '필터 펼치기' : '필터 접기',
                        style: TextStyle(
                          color: primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(
                        _filterCollapsed
                            ? Icons.expand_more
                            : Icons.expand_less,
                        size: 16,
                        color: primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (!_filterCollapsed) ...[
            const SizedBox(height: 6),
            // 1줄: 시간대 칩
            SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _chip(
                    '전체 시간',
                    _timeSlot == CallTimeSlotFilter.all && _exactHour == null,
                    const Color(0xFF3B82F6),
                    Colors.white,
                    () => setState(() {
                      _exactHour = null;
                      _timeSlot = CallTimeSlotFilter.all;
                      _recompute();
                    }),
                  ),
                  _chip(
                    '초저녁 18~21',
                    _timeSlot == CallTimeSlotFilter.evening &&
                        _exactHour == null,
                    const Color(0xFF3B82F6),
                    Colors.white,
                    () => setState(() {
                      _exactHour = null;
                      _timeSlot = CallTimeSlotFilter.evening;
                      _recompute();
                    }),
                  ),
                  _chip(
                    '🔥피크 21~01',
                    _timeSlot == CallTimeSlotFilter.peak && _exactHour == null,
                    const Color(0xFF3B82F6),
                    Colors.white,
                    () => setState(() {
                      _exactHour = null;
                      _timeSlot = CallTimeSlotFilter.peak;
                      _recompute();
                    }),
                  ),
                  _chip(
                    '심야 01~05',
                    _timeSlot == CallTimeSlotFilter.late && _exactHour == null,
                    const Color(0xFF3B82F6),
                    Colors.white,
                    () => setState(() {
                      _exactHour = null;
                      _timeSlot = CallTimeSlotFilter.late;
                      _recompute();
                    }),
                  ),
                  _chip(
                    '주간 05~18',
                    _timeSlot == CallTimeSlotFilter.day && _exactHour == null,
                    const Color(0xFF3B82F6),
                    Colors.white,
                    () => setState(() {
                      _exactHour = null;
                      _timeSlot = CallTimeSlotFilter.day;
                      _recompute();
                    }),
                  ),
                  if (_exactHour != null)
                    _chip(
                      '${_exactHour.toString().padLeft(2, '0')}시 ✕',
                      true,
                      const Color(0xFF6366F1),
                      Colors.white,
                      () => setState(() {
                        _exactHour = null;
                        _recompute();
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            // 2줄: 단가 + 플랫폼 칩
            SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _chip(
                    '전체 단가',
                    _fareFilter == CallFareFilter.all,
                    primary,
                    Colors.black,
                    () => setState(() {
                      _fareFilter = CallFareFilter.all;
                      _recompute();
                    }),
                  ),
                  _chip(
                    '💰3만↑',
                    _fareFilter == CallFareFilter.over30k,
                    primary,
                    Colors.black,
                    () => setState(() {
                      _fareFilter = CallFareFilter.over30k;
                      _recompute();
                    }),
                  ),
                  _chip(
                    '👑5만↑ 꿀콜',
                    _fareFilter == CallFareFilter.over50k,
                    primary,
                    Colors.black,
                    () => setState(() {
                      _fareFilter = CallFareFilter.over50k;
                      _recompute();
                    }),
                  ),
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    color: dividerColor,
                  ),
                  for (final p in const [
                    'all',
                    '카카오',
                    '로지',
                    '콜마너',
                    '티맵',
                    '핸들',
                  ])
                    _chip(
                      p == 'all' ? '전 플랫폼' : p,
                      _platformFilter == p,
                      const Color(0xFF7C3AED),
                      Colors.white,
                      () => setState(() {
                        _platformFilter = p;
                        _recompute();
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // 3줄: 지역/주소 검색
            SizedBox(
              height: 36,
              child: TextField(
                controller: _searchCon,
                onChanged: (_) => setState(() => _recompute()),
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: '지역명·출도착지 검색 (예: 역삼동, 분당, 판교역)',
                  hintStyle: const TextStyle(
                    color: Color(0xFF6E717C),
                    fontSize: 12,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 16,
                    color: Color(0xFF9FA3AE),
                  ),
                  suffixIcon: _searchCon.text.isNotEmpty
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.close,
                            size: 16,
                            color: Color(0xFF9FA3AE),
                          ),
                          onPressed: () {
                            _searchCon.clear();
                            setState(() => _recompute());
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF14171D),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide(color: dividerColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide(color: dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide(color: primary),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(
    String label,
    bool active,
    Color activeBg,
    Color activeFg,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? activeBg : const Color(0xFF14171D),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? activeBg : const Color(0xFF2C2F38),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? activeFg : const Color(0xFF9FA3AE),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKpiStrip(CallPointAnalyticsResult res, {required bool use2x2}) {
    final avgText = res.avgFare > 0
        ? '${(res.avgFare / 10000).toStringAsFixed(1)}만'
        : '-';
    final peakText = res.peakHour != null
        ? '${res.peakHour!.hour.toString().padLeft(2, '0')}시'
        : '-';

    final items = [
      ('조회 콜', '${NumberFormat('#,###').format(res.filteredCount)}건', Colors.white),
      ('평균 단가', avgText, const Color(0xFFFFC700)),
      ('3만↑ 비중', '${res.high30kRatio}%', const Color(0xFFFB7185)),
      ('피크 시간', peakText, const Color(0xFF00E676)),
    ];

    Widget buildCell((String, String, Color) item, {required bool rowStyle}) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: rowStyle ? 10 : 6,
          vertical: rowStyle ? 6 : 6,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1F222A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2C2F38)),
        ),
        child: rowStyle
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      item.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF9FA3AE),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    item.$2,
                    style: TextStyle(
                      color: item.$3,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9FA3AE),
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      item.$2,
                      style: TextStyle(
                        color: item.$3,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
      );
    }

    return Container(
      color: const Color(0xFF14161C),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: use2x2
          ? Column(
              children: [
                Row(
                  children: [
                    Expanded(child: buildCell(items[0], rowStyle: true)),
                    const SizedBox(width: 6),
                    Expanded(child: buildCell(items[1], rowStyle: true)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: buildCell(items[2], rowStyle: true)),
                    const SizedBox(width: 6),
                    Expanded(child: buildCell(items[3], rowStyle: true)),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Expanded(child: buildCell(items[i], rowStyle: false)),
                ],
              ],
            ),
    );
  }

  Widget _buildMapArea() {
    if (kIsWeb) {
      return const Center(
        child: Text(
          '웹 환경에서는 Google 지도를 지원하지 않습니다.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final initialTarget = _userPos != null
        ? LatLng(_userPos!.latitude, _userPos!.longitude)
        : const LatLng(37.5665, 126.9780);
    final initialZoom = _userPos != null ? 13.8 : 10.8;

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: initialTarget,
            zoom: initialZoom,
          ),
          onMapCreated: (ctrl) async {
            if (!_mapController.isCompleted) {
              _mapController.complete(ctrl);
            }
            await _updateVisibleBounds();
          },
          onCameraMove: (pos) {
            _cameraTarget = pos.target;
          },
          onCameraIdle: () {
            _cameraDebounce?.cancel();
            _cameraDebounce = Timer(
              const Duration(milliseconds: 140),
              () => _updateVisibleBounds(),
            );
          },
          onTap: (_) {
            if (_selectedPoint != null || _selectedCoordKey != null) {
              setState(() {
                _selectedPoint = null;
                _selectedCoordKey = null;
                _rebuildMarkers();
              });
            }
          },
          markers: _markers,
          myLocationEnabled: _locationPermissionGranted,
          myLocationButtonEnabled: _locationPermissionGranted,
          compassEnabled: true,
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
        ),

        // 상단 플로팅 컨트롤: 단가 히트 ↔ 플랫폼 + 반경(3/5/10/전체)
        Positioned(
          top: 10,
          left: 10,
          right: 54, // GoogleMap 내위치 버튼 공간 확보
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.9,
            maxScaleFactor: 1.15,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: const Color(0xE6121418),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2C2F38)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _modeToggleBtn(
                        '🔥 단가 히트',
                        _colorMode == CallColorMode.fare,
                        () => setState(() {
                          _colorMode = CallColorMode.fare;
                          _rebuildMarkers();
                        }),
                      ),
                      _modeToggleBtn(
                        '🎨 플랫폼',
                        _colorMode == CallColorMode.platform,
                        () => setState(() {
                          _colorMode = CallColorMode.platform;
                          _rebuildMarkers();
                        }),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: _cycleRadius,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xE6121418),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF00E676).withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 13,
                          color: Color(0xFF00E676),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '반경: ${_radiusFilter.label}',
                          style: const TextStyle(
                            color: Color(0xFF00E676),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 좌측 상단(모드 토글 아래) 마커 범례 — 하단 시트에 가려지지 않음
        Positioned(
          left: 10,
          top: 52,
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.9,
            maxScaleFactor: 1.15,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xE0121418),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFF2C2F38)),
              ),
              child: _colorMode == CallColorMode.fare
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _legendDot(const Color(0xFFEF4444), '5만↑ 꿀콜'),
                        const SizedBox(width: 8),
                        _legendDot(const Color(0xFFF59E0B), '3~5만'),
                        const SizedBox(width: 8),
                        _legendDot(const Color(0xFF3B82F6), '3만 미만'),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _legendDot(const Color(0xFFEAB308), '카카오'),
                        const SizedBox(width: 6),
                        _legendDot(const Color(0xFF22C55E), '로지'),
                        const SizedBox(width: 6),
                        _legendDot(const Color(0xFFA855F7), '콜마너'),
                        const SizedBox(width: 6),
                        _legendDot(const Color(0xFF3B82F6), '티맵'),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _modeToggleBtn(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFC700) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : const Color(0xFF9FA3AE),
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Color(0xFFE5E7EB), fontSize: 10),
        ),
      ],
    );
  }

  List<AnalyticsCallPoint> _activeCallListPoints(CallPointAnalyticsResult res) {
    if (_selectedCoordKey == null) return res.filteredPoints;
    final matched = res.filteredPoints
        .where((p) => _coordKeyOf(p) == _selectedCoordKey)
        .toList();
    if (matched.isNotEmpty) return matched;
    if (_selectedPoint != null) return <AnalyticsCallPoint>[_selectedPoint!];
    return res.filteredPoints;
  }

  Widget _buildAnalyticsPanel(
    CallPointAnalyticsResult res, {
    required ScrollController? scrollController,
    required bool showGrabBar,
    required double sheetViewportHeight,
  }) {
    final cardColor = Theme.of(context).cardTheme.color ?? const Color(0xFF1F222A);
    final dividerColor = Theme.of(context).dividerColor;
    final primary = Theme.of(context).primaryColor;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final callListCount = _activeCallListPoints(res).length;

    Widget headerWidget = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showGrabBar)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '상권 분석',
                  style: TextStyle(
                    color: Color(0xFF9FA3AE),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A4D55),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _snapBtn('지도', () => _animateSheetTo(0.22)),
                    const SizedBox(width: 4),
                    _snapBtn('기본', () => _animateSheetTo(0.44)),
                    const SizedBox(width: 4),
                    _snapBtn('목록', () => _animateSheetTo(0.86)),
                  ],
                ),
              ],
            ),
          ),

        // 3탭 바
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            border: Border(bottom: BorderSide(color: dividerColor)),
          ),
          child: Row(
            children: [
              _sheetTabBtn(0, '🔥 핫스팟 TOP', primary),
              _sheetTabBtn(1, '⏰ 시간·플랫폼', primary),
              _sheetTabBtn(2, '📋 콜 목록 ($callListCount)', primary),
            ],
          ),
        ),
      ],
    );

    if (showGrabBar) {
      headerWidget = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          if (!_sheetController.isAttached || sheetViewportHeight <= 0) return;
          final delta = -(details.primaryDelta ?? 0) / sheetViewportHeight;
          final next = (_sheetController.size + delta).clamp(0.22, 0.86);
          _sheetController.jumpTo(next);
        },
        onVerticalDragEnd: (details) {
          if (!_sheetController.isAttached) return;
          final v = details.primaryVelocity ?? 0;
          final cur = _sheetController.size;
          if (v < -300) {
            _animateSheetTo(cur < 0.44 ? 0.44 : 0.86);
          } else if (v > 300) {
            _animateSheetTo(cur > 0.44 ? 0.44 : 0.22);
          } else {
            const snaps = <double>[0.22, 0.44, 0.86];
            double best = snaps.first;
            for (final s in snaps) {
              if ((cur - s).abs() < (cur - best).abs()) best = s;
            }
            _animateSheetTo(best);
          }
        },
        child: headerWidget,
      );
    }

    return Column(
      children: [
        headerWidget,
        // 탭 콘텐츠: AlwaysScrollableScrollPhysics로 항목 수가 적어도 시트 드래그 100% 보장
        Expanded(
          child: ListView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(12, 10, 12, 18 + bottomInset),
            children: [
              if (_sheetTabIndex == 0) ..._buildHotspotItems(res),
              if (_sheetTabIndex == 1) ..._buildTimePlatformItems(res),
              if (_sheetTabIndex == 2) ..._buildCallListItems(res),
              const SizedBox(height: 10),
              _buildFooterMeta(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _snapBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF14171D),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF2C2F38)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFD1D5DB),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _sheetTabBtn(int index, String label, Color primary) {
    final active = _sheetTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _sheetTabIndex = index);
          _scrollSheetToTop();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? primary : Colors.transparent,
                width: 2.2,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                color: active ? primary : const Color(0xFF9FA3AE),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildHotspotItems(CallPointAnalyticsResult res) {
    final list = res.regionRankings;
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              _selectedRegion != null
                  ? '📍 $_selectedRegion 선택됨 (다시 탭하면 해제)'
                  : '상권을 탭하면 해당 지역으로 이동합니다',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _selectedRegion != null
                    ? const Color(0xFFFFC700)
                    : const Color(0xFF9FA3AE),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sortChip('건수순', !_sortRegionByFare, () {
                setState(() {
                  _sortRegionByFare = false;
                  _recompute();
                });
              }),
              const SizedBox(width: 4),
              _sortChip('단가순', _sortRegionByFare, () {
                setState(() {
                  _sortRegionByFare = true;
                  _recompute();
                });
              }),
            ],
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (list.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Text(
              '조건에 맞는 핫스팟 데이터가 없습니다.',
              style: TextStyle(color: Color(0xFF6E717C), fontSize: 13),
            ),
          ),
        )
      else
        for (int i = 0; i < list.length; i++) _buildHotspotTile(list[i], i),
    ];
  }

  Widget _sortChip(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFC700) : const Color(0xFF1F222A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? const Color(0xFFFFC700) : const Color(0xFF2C2F38),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : const Color(0xFF9FA3AE),
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildHotspotTile(RegionHotspotStat r, int index) {
    final isSelected = _selectedRegion == r.region;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: InkWell(
        onTap: () async {
          setState(() {
            if (isSelected) {
              _selectedRegion = null;
            } else {
              _selectedRegion = r.region;
            }
            _selectedPoint = null;
            _selectedCoordKey = null;
            _recompute();
          });
          if (!isSelected) {
            await _moveCamera(LatLng(r.centerLat, r.centerLng), zoom: 14.2);
            await _updateVisibleBounds();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0x1AFFC700)
                : const Color(0xFF1F222A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFFFC700)
                  : const Color(0xFF2C2F38),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: index < 3
                      ? const Color(0xFFFFC700)
                      : const Color(0xFF2C2F38),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: index < 3 ? Colors.black : const Color(0xFFD1D5DB),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            r.region,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${r.count}건',
                          style: const TextStyle(
                            color: Color(0xFF60A5FA),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '피크 ${r.mainHour} · 최고 ${NumberFormat('#,###').format(r.maxFare)}원',
                      style: const TextStyle(
                        color: Color(0xFF9FA3AE),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${NumberFormat('#,###').format(r.avgFare)}원',
                    style: const TextStyle(
                      color: Color(0xFFFFC700),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text(
                    '평균 단가',
                    style: TextStyle(color: Color(0xFF9FA3AE), fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTimePlatformItems(CallPointAnalyticsResult res) {
    final buckets = res.orderedHourBuckets;
    final maxCnt = buckets.isEmpty
        ? 1
        : buckets.map((b) => b.count).reduce(math.max);

    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '⏰ 시간대별 콜 발생 & 평균 단가 (탭 시 1시간 필터)',
            style: TextStyle(
              color: Color(0xFFFFC700),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_exactHour != null)
            InkWell(
              onTap: () => setState(() {
                _exactHour = null;
                _recompute();
              }),
              child: const Text(
                '전체보기',
                style: TextStyle(color: Color(0xFF60A5FA), fontSize: 11),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (buckets.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(
              '시간대 데이터가 없습니다.',
              style: TextStyle(color: Color(0xFF6E717C), fontSize: 12.5),
            ),
          ),
        )
      else
        for (final b in buckets) _buildHourBar(b, maxCnt),
      const SizedBox(height: 14),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '📊 플랫폼별 콜 비중 & 평균 단가 (탭 시 필터)',
            style: TextStyle(
              color: Color(0xFF4DABF7),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_platformFilter != 'all')
            InkWell(
              onTap: () => setState(() {
                _platformFilter = 'all';
                _selectedPoint = null;
                _selectedCoordKey = null;
                _recompute();
              }),
              child: const Text(
                '전체보기',
                style: TextStyle(color: Color(0xFF60A5FA), fontSize: 11),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (res.platformBreakdown.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(
              '플랫폼 데이터가 없습니다.',
              style: TextStyle(color: Color(0xFF6E717C), fontSize: 12.5),
            ),
          ),
        )
      else
        for (final p in res.platformBreakdown) _buildPlatformBar(p),
    ];
  }

  Widget _buildHourBar(HourBucketStat b, int maxCnt) {
    final isSelected = _exactHour == b.hour;
    final isPeak = b.hour >= 21 || b.hour <= 1;
    final ratio = (b.count / maxCnt).clamp(0.08, 1.0);
    final hLabel =
        '${b.hour.toString().padLeft(2, '0')}시 ~ ${((b.hour + 1) % 24).toString().padLeft(2, '0')}시';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => setState(() {
          _exactHour = isSelected ? null : b.hour;
          _selectedPoint = null;
          _selectedCoordKey = null;
          _recompute();
        }),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0x2E6366F1)
                : const Color(0xFF1F222A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF818CF8)
                  : const Color(0xFF2C2F38),
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isPeak) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x28F43F5E),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '피크',
                            style: TextStyle(
                              color: Color(0xFFFB7185),
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Flexible(
                    child: Text(
                      '${b.count}건 · 평균 ${NumberFormat('#,###').format(b.avgFare)}원',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFC700),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor: const Color(0xFF121418),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isPeak ? const Color(0xFF00E676) : const Color(0xFF3B82F6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlatformBar(PlatformBreakdownStat p) {
    final c = Color(p.colorValue);
    final isSelected = _platformFilter == p.key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: InkWell(
        onTap: () => setState(() {
          _platformFilter = isSelected ? 'all' : p.key;
          _selectedPoint = null;
          _selectedCoordKey = null;
          _recompute();
        }),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? c.withValues(alpha: 0.16)
                : const Color(0xFF1F222A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? c : const Color(0xFF2C2F38),
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${p.name} (${p.count}건 · ${p.ratio}%)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: c.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '선택됨',
                            style: TextStyle(
                              color: c,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '평균 ${NumberFormat('#,###').format(p.avgFare)}원',
                    style: const TextStyle(
                      color: Color(0xFFFFC700),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: (p.ratio / 100.0).clamp(0.05, 1.0),
                  minHeight: 6,
                  backgroundColor: const Color(0xFF121418),
                  valueColor: AlwaysStoppedAnimation<Color>(c),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activeFilterBadge(String label, VoidCallback onRemove) {
    return InkWell(
      onTap: onRemove,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x26FFC700),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x88FFC700)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFFFC700),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.close, size: 13, color: Color(0xFFFFC700)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCallListItems(CallPointAnalyticsResult res) {
    final list = _activeCallListPoints(res);
    final displayCount = math.min(list.length, 200);

    final List<Widget> activeChips = [
      if (_selectedCoordKey != null)
        _activeFilterBadge(
          '📌 선택 좌표 ${list.length}건 · 전체보기',
          () => setState(() {
            _selectedCoordKey = null;
            _selectedPoint = null;
            _rebuildMarkers();
          }),
        ),
      if (_selectedRegion != null)
        _activeFilterBadge(
          '📍 $_selectedRegion',
          () => setState(() {
            _selectedRegion = null;
            _selectedCoordKey = null;
            _selectedPoint = null;
            _recompute();
          }),
        ),
      if (_exactHour != null)
        _activeFilterBadge(
          '⏰ ${_exactHour.toString().padLeft(2, '0')}시',
          () => setState(() {
            _exactHour = null;
            _selectedCoordKey = null;
            _selectedPoint = null;
            _recompute();
          }),
        ),
      if (_platformFilter != 'all')
        _activeFilterBadge(
          '플랫폼: $_platformFilter',
          () => setState(() {
            _platformFilter = 'all';
            _selectedCoordKey = null;
            _selectedPoint = null;
            _recompute();
          }),
        ),
    ];

    if (displayCount == 0) {
      return [
        if (activeChips.isNotEmpty) ...[
          Wrap(spacing: 6, runSpacing: 6, children: activeChips),
          const SizedBox(height: 10),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Text(
              '조건에 맞는 콜 데이터가 없습니다.',
              style: TextStyle(color: Color(0xFF6E717C), fontSize: 13),
            ),
          ),
        ),
      ];
    }

    return [
      if (activeChips.isNotEmpty) ...[
        Wrap(spacing: 6, runSpacing: 6, children: activeChips),
        const SizedBox(height: 8),
      ],
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          _selectedCoordKey != null
              ? '선택한 좌표의 콜 $displayCount건 (탭 시 지도 이동)'
              : '표시 $displayCount건 / 필터 결과 ${NumberFormat('#,###').format(list.length)}건 (탭 시 지도 이동)',
          style: const TextStyle(color: Color(0xFF9FA3AE), fontSize: 11.5),
        ),
      ),
      for (int i = 0; i < displayCount; i++) _buildCallCard(list[i]),
    ];
  }

  Widget _buildCallCard(AnalyticsCallPoint pt) {
    final pColor = Color(
      CallPointAnalyticsService.platformColorValue(pt.programName),
    );
    final isHighlighted = _selectedCoordKey != null &&
        _coordKeyOf(pt) == _selectedCoordKey;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () async {
          setState(() {
            _selectedPoint = pt;
            _selectedCoordKey = _coordKeyOf(pt);
            _rebuildMarkers();
          });
          await _moveCamera(LatLng(pt.lat, pt.lng), zoom: 15.2);
          await _updateVisibleBounds();
          _animateSheetTo(0.22);
        },
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: const Color(0xFF282B33),
            borderRadius: BorderRadius.circular(13),
            border: isHighlighted
                ? Border(
                    left: BorderSide(color: pColor, width: 4),
                    top: const BorderSide(color: Color(0x88FFC700)),
                    right: const BorderSide(color: Color(0x88FFC700)),
                    bottom: const BorderSide(color: Color(0x88FFC700)),
                  )
                : Border(left: BorderSide(color: pColor, width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: pColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            pt.regionName,
                            style: TextStyle(
                              color: pColor,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (pt.displayDateTime.isNotEmpty)
                          Text(
                            pt.displayDateTime,
                            style: const TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 11.5,
                            ),
                          ),
                        if (pt.fare > 0)
                          Text(
                            '${NumberFormat('#,###').format(pt.fare)}원',
                            style: const TextStyle(
                              color: Color(0xFFFFC700),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x1A60A5FA),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      pt.programName,
                      style: const TextStyle(
                        color: Color(0xFF60A5FA),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                '● ${pt.startLocation}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFF3F4F6),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '● ${pt.endLocation}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFD1D5DB),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooterMeta() {
    String updatedLabel = '매일 새벽 6시 자동 갱신';
    if (_updatedAtIso.isNotEmpty) {
      final dt = DateTime.tryParse(_updatedAtIso)?.toLocal();
      if (dt != null) {
        final yy = (dt.year % 100).toString().padLeft(2, '0');
        final mo = dt.month.toString().padLeft(2, '0');
        final dd = dt.day.toString().padLeft(2, '0');
        final hh = dt.hour.toString().padLeft(2, '0');
        final mm = dt.minute.toString().padLeft(2, '0');
        updatedLabel = '데이터 기준: $yy.$mo.$dd $hh:$mm${_fromCache ? ' (캐시)' : ''}';
      }
    }
    return Center(
      child: Text(
        '$updatedLabel · 누적 ${NumberFormat('#,###').format(_allPoints.length)}건',
        style: const TextStyle(color: Color(0xFF6E717C), fontSize: 11),
      ),
    );
  }
}
