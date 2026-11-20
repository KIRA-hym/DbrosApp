import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'
    if (dart.library.html) '../utils/maps_web_stub.dart';

import '../utils/address_normalize.dart';
import '../utils/geocoding_utils.dart';

/// 출발/도착 좌표를 지도에서 고르고 [LatLng]을 반환합니다. 취소 시 `null`.
class LocationPickMapPage extends StatefulWidget {
  const LocationPickMapPage({
    super.key,
    required this.addressQuery,
    this.initialLatLng,
    this.title = '위치 선택',
  });

  final String addressQuery;
  final LatLng? initialLatLng;
  final String title;

  @override
  State<LocationPickMapPage> createState() => _LocationPickMapPageState();
}

class _LocationPickMapPageState extends State<LocationPickMapPage> {
  final TextEditingController _searchCon = TextEditingController();
  GoogleMapController? _mapController;
  late LatLng _markerPosition;
  bool _loading = true;
  bool _searching = false;
  bool _userMovedMap = false;
  bool _programmaticMove = false;
  String _lastSearchedQuery = '';
  String _pickedAddressPreview = '';
  Timer? _reverseGeoDebounce;
  static const LatLng _fallbackSeoul = LatLng(37.5665, 126.9780);

  @override
  void initState() {
    super.initState();
    final initialQuery = normalizeAddressForGeocode(widget.addressQuery);
    final seedText = initialQuery.isNotEmpty
        ? initialQuery
        : widget.addressQuery.trim();
    _searchCon.text = seedText;
    _lastSearchedQuery = seedText;
    _markerPosition = widget.initialLatLng ?? _fallbackSeoul;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _reverseGeoDebounce?.cancel();
    _searchCon.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (widget.initialLatLng != null &&
        GeocodingUtils.isValidSouthKoreaCoord(
          widget.initialLatLng!.latitude,
          widget.initialLatLng!.longitude,
        )) {
      _markerPosition = widget.initialLatLng!;
      if (mounted) setState(() => _loading = false);
      _moveCamera(_markerPosition);
      _scheduleReverseGeocode(_markerPosition);
      return;
    }

    final rawQuery = widget.addressQuery.trim();
    var placed = false;

    if (rawQuery.isNotEmpty) {
      try {
        final loc = await GeocodingUtils.getCoordinateFromAddressFallback(
          rawQuery,
        );
        if (loc != null) {
          _markerPosition = LatLng(loc.latitude, loc.longitude);
          placed = true;
        }
      } catch (_) {}
    }

    if (!placed) {
      final ok = await _ensureLocationPermission();
      if (ok) {
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
            ),
          ).timeout(const Duration(seconds: 12));
          _markerPosition = LatLng(pos.latitude, pos.longitude);
          placed = true;
        } catch (_) {}
      }
    }

    if (!placed) {
      _markerPosition = _fallbackSeoul;
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
      _moveCamera(_markerPosition);
      _scheduleReverseGeocode(_markerPosition);
      if (!placed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('주소를 인식하지 못했습니다. 상단 검색이나 지도를 움직여 위치를 맞춰 주세요.'),
          ),
        );
      }
    }
  }

  Future<bool> _ensureLocationPermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  void _moveCamera(LatLng target, {double zoom = 15}) {
    _programmaticMove = true;
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(target, zoom),
    );
  }

  void _scheduleReverseGeocode(LatLng pos) {
    _reverseGeoDebounce?.cancel();
    _reverseGeoDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final placemarks = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        ).timeout(const Duration(seconds: 3));
        if (!mounted || placemarks.isEmpty) return;
        final p = placemarks.first;
        final parts = <String>[
          if ((p.administrativeArea ?? '').trim().isNotEmpty)
            p.administrativeArea!.trim(),
          if ((p.subLocality ?? '').trim().isNotEmpty)
            p.subLocality!.trim()
          else if ((p.locality ?? '').trim().isNotEmpty)
            p.locality!.trim(),
          if ((p.thoroughfare ?? '').trim().isNotEmpty)
            p.thoroughfare!.trim(),
          if ((p.subThoroughfare ?? '').trim().isNotEmpty)
            p.subThoroughfare!.trim(),
        ];
        final label = parts.join(' ').trim();
        setState(() {
          _pickedAddressPreview = label;
        });
      } catch (_) {}
    });
  }

  Future<bool> _runSearch() async {
    final raw = _searchCon.text.trim();
    if (raw.isEmpty) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('검색할 주소를 입력해 주세요.')),
      );
      return false;
    }
    setState(() => _searching = true);
    try {
      final loc = await GeocodingUtils.getCoordinateFromAddressFallback(raw);
      if (!mounted) return false;
      if (loc == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('검색 결과가 없습니다. 주변 역이나 동명으로 시도해 주세요.')),
        );
        return false;
      }
      final nextPos = LatLng(loc.latitude, loc.longitude);
      setState(() {
        _markerPosition = nextPos;
        _lastSearchedQuery = raw;
        _userMovedMap = false;
      });
      _moveCamera(_markerPosition);
      _scheduleReverseGeocode(_markerPosition);
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('검색에 실패했습니다. 네트워크와 입력을 확인해 주세요.')),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _onConfirm() async {
    if (_searching) return;
    final typed = _searchCon.text.trim();
    // 사용자가 검색창만 새로 입력하고 '검색'을 누르지 않은 채 지도를 움직이지 않았다면 검색 먼저 시도
    if (!_userMovedMap &&
        typed.isNotEmpty &&
        typed != _lastSearchedQuery) {
      final ok = await _runSearch();
      if (!mounted || !ok) return;
    }
    Navigator.of(context).pop<LatLng?>(_markerPosition);
  }

  Widget _buildCenterPinOverlay() {
    // Shorebird 에셋 트리쉐이킹 보호: 신규 Icon 위젯 대신 순수 도형으로 중앙 핀 렌더링
    return IgnorePointer(
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC700),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 2.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x88000000),
                      blurRadius: 6,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              CustomPaint(
                size: const Size(12, 10),
                painter: _PinTipPainter(),
              ),
              Container(
                width: 6,
                height: 3,
                decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final coordLabel =
        '${_markerPosition.latitude.toStringAsFixed(5)}, ${_markerPosition.longitude.toStringAsFixed(5)}';
    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop<LatLng?>(null),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCon,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '동·번지·건물명 검색',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                        filled: true,
                        fillColor: Theme.of(context).cardTheme.color!,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Colors.white10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Colors.white10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFFFC700),
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _runSearch(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _searching ? null : _runSearch,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFFC700),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    child: Text(_searching ? '검색중' : '검색'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  if (!_loading) ...[
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _markerPosition,
                        zoom: 15,
                      ),
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                      onMapCreated: (c) {
                        _mapController = c;
                        _moveCamera(_markerPosition);
                      },
                      myLocationEnabled: true,
                      onCameraMove: (CameraPosition pos) {
                        _markerPosition = pos.target;
                        if (!_programmaticMove) {
                          _userMovedMap = true;
                        }
                      },
                      onCameraIdle: () {
                        _programmaticMove = false;
                        if (mounted) {
                          setState(() {});
                        }
                        _scheduleReverseGeocode(_markerPosition);
                      },
                      onTap: (latLng) {
                        setState(() {
                          _markerPosition = latLng;
                          _userMovedMap = true;
                        });
                        _mapController?.animateCamera(
                          CameraUpdate.newLatLng(latLng),
                        );
                        _scheduleReverseGeocode(latLng);
                      },
                    ),
                    _buildCenterPinOverlay(),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16181D).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: const Text(
                          '지도를 움직이거나 탭해 중앙 핀을 맞춰 주세요\n검색이 안 되면 주변 역·동명으로 검색해 주세요',
                          style: TextStyle(
                            color: Color(0xFFFFC700),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16181D).withValues(alpha: 0.90),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          _pickedAddressPreview.isNotEmpty
                              ? '선택 위치: $_pickedAddressPreview ($coordLabel)'
                              : '선택 좌표: $coordLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ] else
                    const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFFC700),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop<LatLng?>(null),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _onConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC700),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('등록'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinTipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0xFFFFC700);
    final stroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
