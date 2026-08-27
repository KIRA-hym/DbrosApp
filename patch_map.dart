import 'dart:io';

void main() {
  var file = File('lib/screens/call_point_map_page.dart');
  var content = file.readAsStringSync();

  // 1. Add state variables
  if (!content.contains('String? _selectedLocKey;')) {
    content = content.replaceAll(
      'BitmapDescriptor? _shuttleIcon;',
      '''BitmapDescriptor? _shuttleIcon;
  BitmapDescriptor? _logIconMineSelected;
  BitmapDescriptor? _logIconOtherSelected;
  BitmapDescriptor? _refIconSelected;
  BitmapDescriptor? _restroomIconSelected;
  BitmapDescriptor? _shuttleIconSelected;
  
  String? _selectedLocKey;
  final Map<String, List<CallPointData>> _groupedPoints = {};'''
    );
  }

  // 2. Replace _precacheIcons
  var precacheStart = content.indexOf('Future<void> _precacheIcons() async {');
  var precacheEnd = content.indexOf('}', precacheStart) + 1;
  content = content.replaceRange(precacheStart, precacheEnd, '''Future<void> _precacheIcons() async {
    _logIconMine ??= await MarkerUtils.createCustomMarkerBitmap('내', bgColor: const Color(0xFFEC4899), size: 65, borderColor: Colors.black, dy: 1.0);
    _logIconOther ??= await MarkerUtils.createCustomMarkerBitmap('@', bgColor: const Color(0xFF3B82F6), size: 65, borderColor: Colors.black, dy: 0.5);
    _refIcon ??= await MarkerUtils.createCustomMarkerBitmap('공', bgColor: const Color(0xFFFBBF24), size: 65, borderColor: Colors.black, textScale: 1.3, dy: -2.0);
    _restroomIcon ??= await MarkerUtils.createCustomMarkerBitmap('??', bgColor: Colors.white, textColor: Colors.black87, size: 65, borderColor: Colors.black, dy: 0.0);
    _shuttleIcon ??= await MarkerUtils.createCustomMarkerBitmap('??', bgColor: Colors.white, textColor: Colors.black87, size: 65, borderColor: Colors.black, dy: 0.0);
    
    _logIconMineSelected ??= await MarkerUtils.createCustomMarkerBitmap('내', bgColor: const Color(0xFFEC4899), size: 85, borderColor: Colors.white, dy: 1.0);
    _logIconOtherSelected ??= await MarkerUtils.createCustomMarkerBitmap('@', bgColor: const Color(0xFF3B82F6), size: 85, borderColor: Colors.white, dy: 0.5);
    _refIconSelected ??= await MarkerUtils.createCustomMarkerBitmap('공', bgColor: const Color(0xFFFBBF24), size: 85, borderColor: Colors.white, textScale: 1.3, dy: -2.0);
    _restroomIconSelected ??= await MarkerUtils.createCustomMarkerBitmap('??', bgColor: Colors.white, textColor: Colors.black87, size: 85, borderColor: Colors.yellowAccent, dy: 0.0);
    _shuttleIconSelected ??= await MarkerUtils.createCustomMarkerBitmap('??', bgColor: Colors.white, textColor: Colors.black87, size: 85, borderColor: Colors.yellowAccent, dy: 0.0);
  }''');

  // 3. Replace _applyFilter
  var applyFilterStart = content.indexOf('void _applyFilter() {');
  var applyFilterEnd = content.indexOf('void _showFilterBottomSheet() {');
  content = content.replaceRange(applyFilterStart, applyFilterEnd, '''void _applyFilter() {
    List<CallPointData> filtered = _allPoints.where((p) {
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
    final locationCounts = <String, int>{};
    _groupedPoints.clear();
    
    int index = 0;
    for (final point in filtered) {
      final locKey = '\,\';
      _groupedPoints.putIfAbsent(locKey, () => []).add(point);
      
      final overlapCount = locationCounts[locKey] ?? 0;
      locationCounts[locKey] = overlapCount + 1;
      
      double jitterLat = point.position.latitude;
      double jitterLng = point.position.longitude;
      
      if (overlapCount > 0) {
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

  ''');

  // 4. Replace _infoWindowForPoint, _onMarkerTap, _buildMarker
  var infoWindowStart = content.indexOf('InfoWindow _infoWindowForPoint(CallPointData point) {');
  var buildMarkerEnd = content.indexOf('Future<BitmapDescriptor> _getMarkerBitmap(int size, {String? text');
  
  if (infoWindowStart != -1 && buildMarkerEnd != -1) {
    content = content.replaceRange(infoWindowStart, buildMarkerEnd, '''void _onMarkerTap(String locKey) {
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
              child: Text('\ 원', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFFBBF24))),
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
      markerId: MarkerId('\_\'),
      position: position,
      onTap: () => _onMarkerTap(locKey),
      icon: icon,
      zIndex: zIndex,
    );
  }

  ''');
  }

  file.writeAsStringSync(content);
  print('Done patching.');
}
