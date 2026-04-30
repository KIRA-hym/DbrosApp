import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../utils/address_normalize.dart';

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
  static const LatLng _fallbackSeoul = LatLng(37.5665, 126.9780);

  @override
  void initState() {
    super.initState();
    _markerPosition = widget.initialLatLng ?? _fallbackSeoul;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _searchCon.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (widget.initialLatLng != null) {
      _markerPosition = widget.initialLatLng!;
      if (mounted) setState(() => _loading = false);
      _moveCamera(_markerPosition);
      return;
    }

    final normalized = normalizeAddressForGeocode(widget.addressQuery);
    var placed = false;

    if (normalized.isNotEmpty) {
      try {
        final list = await locationFromAddress(normalized)
            .timeout(const Duration(seconds: 12), onTimeout: () => <Location>[]);
        if (list.isNotEmpty) {
          _markerPosition = LatLng(list.first.latitude, list.first.longitude);
          placed = true;
        }
      } catch (_) {}
    }

    if (!placed) {
      final ok = await _ensureLocationPermission();
      if (ok) {
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
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
      if (!placed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('주소를 인식하지 못했습니다. 상단 검색으로 위치를 찾아 주세요.'),
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
    return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
  }

  void _moveCamera(LatLng target, {double zoom = 15}) {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(target, zoom),
    );
  }

  Future<void> _runSearch() async {
    final q = normalizeAddressForGeocode(_searchCon.text);
    if (q.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('검색할 주소를 입력해 주세요.')),
      );
      return;
    }
    try {
      final list = await locationFromAddress(q).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (list.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('검색 결과가 없습니다. 다른 표현으로 시도해 주세요.')),
        );
        return;
      }
      final loc = list.first;
      setState(() {
        _markerPosition = LatLng(loc.latitude, loc.longitude);
      });
      _moveCamera(_markerPosition);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('검색에 실패했습니다. 네트워크와 입력을 확인해 주세요.')),
      );
    }
  }

  Set<Marker> get _markers => {
        Marker(
          markerId: const MarkerId('pick'),
          position: _markerPosition,
          draggable: true,
          onDragEnd: (LatLng pos) {
            setState(() => _markerPosition = pos);
          },
        ),
      };

  @override
  Widget build(BuildContext context) {
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
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
                        filled: true,
                        fillColor: const Color(0xFF1F222A),
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
                          borderSide: const BorderSide(color: Color(0xFFFFC700)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _runSearch(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _runSearch,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFFC700),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    child: const Text('검색'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  if (!_loading)
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _markerPosition,
                        zoom: 15,
                      ),
                      markers: _markers,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                      onMapCreated: (c) {
                        _mapController = c;
                        _moveCamera(_markerPosition);
                      },
                      myLocationEnabled: true,
                      onTap: (latLng) {
                        setState(() => _markerPosition = latLng);
                      },
                    )
                  else
                    const Center(
                      child: CircularProgressIndicator(color: Color(0xFFFFC700)),
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
                      onPressed: () =>
                          Navigator.of(context).pop<LatLng?>(_markerPosition),
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
