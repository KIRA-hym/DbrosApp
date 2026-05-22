import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../services/db_helper.dart';

class NearbyHotspotMapPage extends StatefulWidget {
  const NearbyHotspotMapPage({super.key});

  @override
  State<NearbyHotspotMapPage> createState() => _NearbyHotspotMapPageState();
}

class _NearbyHotspotMapPageState extends State<NearbyHotspotMapPage> {
  final Completer<GoogleMapController> _controller = Completer();
  Position? _currentPosition;
  bool _loading = true;
  Set<Marker> _markers = {};
  int _hotspotCount = 0;

  @override
  void initState() {
    super.initState();
    _initMap();
  }

  Future<void> _initMap() async {
    try {
      final hasPermission = await _handleLocationPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('위치 권한이 거부되어 내 주변 꿀콜 지도를 사용할 수 없습니다.')),
          );
        }
        setState(() => _loading = false);
        return;
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (_currentPosition != null) {
        await _loadNearbyHotspots();
      }
    } catch (e) {
      debugPrint('위치 가져오기 오류: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<bool> _handleLocationPermission() async {
    if (kIsWeb) return true; // Web stubs usually return true or bypass
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

  Future<void> _loadNearbyHotspots() async {
    if (_currentPosition == null) return;
    final pos = _currentPosition!;

    final db = await DriveLogDatabase.instance.database;
    final logs = await db.query('drive_logs', orderBy: 'id DESC');

    final Set<Marker> markers = {};
    int count = 0;

    for (var log in logs) {
      final startLat = (log['start_lat'] as num?)?.toDouble();
      final startLng = (log['start_lng'] as num?)?.toDouble();

      if (startLat != null && startLng != null) {
        final distance = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          startLat,
          startLng,
        );

        // 5000m (5km) 이내 필터링
        if (distance <= 5000) {
          final id = log['id'].toString();
          final driveTime = log['drive_time']?.toString() ?? '';
          final program = log['program']?.toString() ?? '앱';
          final gross = (log['gross_fare'] as num?)?.toInt() ?? 0;
          final tip = (log['waypoint_tip'] as num?)?.toInt() ?? 0;
          final income = gross + tip;
          
          final startLoc = log['start_location']?.toString() ?? '';
          final endLoc = log['end_location']?.toString() ?? '';
          final snippetText = startLoc.isNotEmpty ? '$startLoc -> $endLoc' : '';

          // 시간대별 마커 색상 구분 (대략적인 파싱)
          double hue = BitmapDescriptor.hueViolet; // 밤/심야 기본
          try {
            if (driveTime.isNotEmpty) {
              final parts = driveTime.split(':');
              if (parts.isNotEmpty) {
                final hour = int.parse(parts[0]);
                if (hour >= 6 && hour < 18) {
                  hue = BitmapDescriptor.hueOrange; // 낮 콜
                }
              }
            }
          } catch (_) {}

          markers.add(
            Marker(
              markerId: MarkerId('hotspot_$id'),
              position: LatLng(startLat, startLng),
              icon: BitmapDescriptor.defaultMarkerWithHue(hue),
              infoWindow: InfoWindow(
                title: '$driveTime / $program / ${NumberFormat('#,###').format(income)}원',
                snippet: snippetText,
              ),
            ),
          );
          count++;
        }
      }
    }

    if (mounted) {
      setState(() {
        _markers = markers;
        _hotspotCount = count;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('내 주변 꿀콜 지도', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            if (!_loading && _currentPosition != null)
              Text(
                '반경 5km 이내 과거 콜: $_hotspotCount건',
                style: const TextStyle(fontSize: 12, color: Color(0xFF9FA3AE)),
              ),
          ],
        ),
        backgroundColor: const Color(0xFF121418),
        elevation: 0,
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
          },
          markers: _markers,
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          compassEnabled: true,
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
        ),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF16181D).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFC700).withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFFFFC700), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '주황색 핀은 낮(06~18시), 보라색 핀은 밤(18~06시)에 수행한 콜입니다. 핀을 눌러 상세 정보를 확인하세요.',
                    style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
