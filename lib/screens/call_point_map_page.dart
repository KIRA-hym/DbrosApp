import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' hide Cluster, ClusterManager;
import 'package:google_maps_cluster_manager_2/google_maps_cluster_manager_2.dart';
import 'package:geocoding/geocoding.dart';

import '../services/db_helper.dart';

class CallPointData with ClusterItem {
  final Map<String, dynamic> data;
  final LatLng position;

  CallPointData({required this.data, required this.position});

  @override
  LatLng get location => position;
}

enum MapFilterMode { radar, reference }

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
  String _mapTitle = "주변 콜맵";
  
  MapFilterMode _currentMode = MapFilterMode.radar;
  List<CallPointData> _allPoints = [];
  
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
      stopClusteringZoom: 16.0,
    );
  }

  void _updateMarkers(Set<Marker> markers) {
    setState(() {
      _markers = markers;
    });
  }

  Future<void> _initMap() async {
    try {
      final hasPermission = await _handleLocationPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('위치 권한이 거부되어 지도를 사용할 수 없습니다.')),
          );
        }
        setState(() => _loading = false);
        return;
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      ).catchError((_) => Geolocator.getLastKnownPosition());

      if (_currentPosition != null) {
        await _reverseGeocode(_currentPosition!);
        await _loadData();
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
      List<Placemark> placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        final pm = placemarks.first;
        final String locality = pm.locality ?? pm.administrativeArea ?? '';
        final String subLocality = pm.subLocality ?? pm.thoroughfare ?? '';
        setState(() {
          _mapTitle = "${locality} ${subLocality} 주변 콜맵".trim();
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
    final List<Map<String, dynamic>> rows = await db.query('call_points');
    
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
  }

  void _applyFilter() {
    List<CallPointData> filtered = [];
    if (_currentMode == MapFilterMode.radar) {
      filtered = _allPoints.where((p) => p.data['type'] == 'log').toList();
    } else {
      filtered = _allPoints.where((p) => p.data['type'] == 'reference').toList();
    }
    _manager.setItems(filtered);
  }

  Future<Marker> _markerBuilder(Cluster<CallPointData> cluster) async {
    Color color = Colors.red;
    bool isHeart = false;
    bool isStar = false;

    if (!cluster.isMultiple) {
      final data = cluster.items.first.data;
      if (data['type'] == 'log') {
        isHeart = true;
        color = (data['is_mine'] == 1) ? const Color(0xFFFF5252) : Colors.lightBlueAccent;
      } else {
        isStar = true;
        color = Colors.purpleAccent;
      }
      return Marker(
        markerId: MarkerId(cluster.getId()),
        position: cluster.location,
        onTap: () => _showClusterDetails(cluster),
        icon: await _getMarkerBitmap(80, color: color, isHeart: isHeart, isStar: isStar),
      );
    } else {
      // Cluster
      if (_currentMode == MapFilterMode.radar) {
        color = const Color(0xFFFFC700); // 옐로우 계열로 클러스터 표시
      } else {
        color = Colors.purple;
      }
      return Marker(
        markerId: MarkerId(cluster.getId()),
        position: cluster.location,
        onTap: () {
          _showClusterDetails(cluster);
        },
        icon: await _getMarkerBitmap(100, text: cluster.count.toString(), color: color),
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
        style: TextStyle(fontSize: size / 2.5, color: Colors.white, fontWeight: FontWeight.bold),
      );
      painter.layout();
      painter.paint(canvas, Offset(size / 2 - painter.width / 2, size / 2 - painter.height / 2));
    } else {
      if (isStar) {
        _drawStar(canvas, Offset(size/2, size/2), size/2.0, paint);
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
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
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

  void _showClusterDetails(Cluster<CallPointData> cluster) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E2128),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          height: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cluster.isMultiple ? '선택된 좌표 목록 (${cluster.count}건)' : '상세 정보',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: cluster.items.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white12),
                  itemBuilder: (context, index) {
                    final data = cluster.items.toList()[index].data;
                    final startLoc = data['start_location'] ?? '';
                    final endLoc = data['end_location'] ?? '';
                    final isMine = data['is_mine'] == 1;
                    final driveTime = data['drive_time']?.toString() ?? '';
                    
                    String displayLoc = startLoc;
                    if (data['type'] == 'reference' && startLoc.contains('(') && startLoc.contains(')')) {
                      final match = RegExp(r'\((.*?)\)').firstMatch(startLoc);
                      if (match != null) {
                        displayLoc = match.group(1) ?? startLoc;
                      }
                    }

                    bool isNight = false;
                    if (driveTime.isNotEmpty) {
                      try {
                        final hour = int.parse(driveTime.split(':')[0]);
                        if (hour < 6 || hour >= 18) isNight = true;
                      } catch (_) {}
                    }
                    
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        data['type'] == 'log' 
                          ? (isMine ? Icons.favorite : Icons.favorite_border)
                          : Icons.star,
                        color: data['type'] == 'log' 
                          ? (isMine ? const Color(0xFFFF5252) : Colors.lightBlueAccent)
                          : Colors.purpleAccent,
                      ),
                      title: Text(
                        data['type'] == 'log' ? '$startLoc -> $endLoc' : displayLoc,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      trailing: data['type'] == 'log' 
                          ? Text(
                              isNight ? '🌙' : '🌞',
                              style: const TextStyle(fontSize: 18),
                            )
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        title: Text(_mapTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF121418),
        elevation: 0,
        actions: [
          _buildFilterTabs(),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFC700)),
            )
          : _currentPosition == null
              ? const Center(
                  child: Text('위치 정보를 가져올 수 없습니다.', style: TextStyle(color: Colors.white)),
                )
              : _buildMap(),
    );
  }

  Widget _buildFilterTabs() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _tabButton("콜레이더", MapFilterMode.radar),
        _tabButton("콜포인트", MapFilterMode.reference),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _tabButton(String text, MapFilterMode mode) {
    final isSelected = _currentMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentMode = mode;
        });
        _applyFilter();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFC700) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFFC700)),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? Colors.black : const Color(0xFFFFC700),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    if (kIsWeb) {
      return const Center(
        child: Text(
          '웹 환경에서는 지도를 지원하지 않습니다.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final initialPos = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: initialPos,
            zoom: 13.0,
          ),
          onMapCreated: (GoogleMapController controller) {
            _controller.complete(controller);
            _manager.setMapId(controller.mapId);
          },
          onCameraMove: _manager.onCameraMove,
          onCameraIdle: _manager.updateMap,
          markers: _markers,
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          compassEnabled: true,
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
        ),
        _buildLegend(),
      ],
    );
  }

  Widget _buildLegend() {
    if (_currentMode != MapFilterMode.radar) return const SizedBox.shrink();

    return Positioned(
      top: 16,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF16181D).withOpacity(0.9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _legendItem(const Color(0xFFFF5252), '내 좌표 (일지)'),
            const SizedBox(height: 4),
            _legendItem(Colors.lightBlueAccent, '공유된 좌표 (가져오기)'),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.favorite, color: color, size: 16),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}
