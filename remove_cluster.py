import re

with open('lib/screens/call_point_map_page.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Remove ClusterManager imports
content = re.sub(r"import 'package:google_maps_cluster_manager_2.*?\n", '', content, flags=re.DOTALL)
content = re.sub(r"    if \(dart.library.html\) '\.\./utils/cluster_manager_web_stub\.dart';\n", '', content)

# 2. Remove ClusterItem from CallPointData
content = content.replace('class CallPointData with ClusterItem {', 'class CallPointData {')
content = re.sub(r'  @override\n  LatLng get location => position;\n', '', content)

# 3. Remove _manager variable
content = re.sub(r'  late ClusterManager _manager;\n', '', content)

# 4. Remove _initClusterManager() and _updateMarkers()
content = re.sub(r'  ClusterManager _initClusterManager\(\) \{.*?\}\n', '', content, flags=re.DOTALL)
content = re.sub(r'  void _updateMarkers\(Set<Marker> markers\) \{.*?\}\n', '', content, flags=re.DOTALL)

# 5. Remove _manager from initState
content = re.sub(r'    _manager = _initClusterManager\(\);\n', '', content)

# 6. Remove _manager.updateMap() from _focusOnCurrentLocation
content = re.sub(r'      _manager\.updateMap\(\);\n', '', content)

# 7. Rewrite _applyFilter
old_apply_filter = '''  void _applyFilter() {
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
    _manager.setItems(filtered);
  }'''

new_apply_filter = '''  void _applyFilter() {
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
  }'''
content = content.replace(old_apply_filter, new_apply_filter)

# 8. Rewrite _infoWindowForCluster to just use point directly
content = re.sub(r'  InfoWindow _infoWindowForCluster\(Cluster<CallPointData> cluster\) \{.*?\n  \}\n\n', '', content, flags=re.DOTALL)

# 9. Rewrite _onMarkerTap
old_on_marker_tap = '''  Future<void> _onMarkerTap(Cluster<CallPointData> cluster) async {
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
  }'''
new_on_marker_tap = '''  Future<void> _onMarkerTap(CallPointData point) async {
    if (!_controller.isCompleted) return;
    try {
      final controller = await _controller.future;
      await controller.showMarkerInfoWindow(MarkerId(point.data['id'].toString()));
    } catch (e) {
      debugPrint('마커 InfoWindow 표시 오류: $e');
    }
  }'''
content = content.replace(old_on_marker_tap, new_on_marker_tap)

# 10. Rewrite _markerBuilder to _buildMarker
old_marker_builder = '''  Future<Marker> _markerBuilder(Cluster<CallPointData> cluster) async {
    final infoWindow = _infoWindowForCluster(cluster);
    final markerId = MarkerId(cluster.getId());

    // 클러스터 여부 상관없이 첫 번째 마커의 데이터로 아이콘 렌더링 (줌아웃 시 겹쳐서 단일 마커로 보이게 함)
    final data = cluster.items.first.data;'''
new_marker_builder = '''  Marker _buildMarker(CallPointData point) {
    final data = point.data;
    final infoWindow = _infoWindowForPoint(point);
    final markerId = MarkerId(data['id'].toString());'''
content = content.replace(old_marker_builder, new_marker_builder)

content = content.replace('onTap: () => _onMarkerTap(cluster),', 'onTap: () => _onMarkerTap(point),')

# 11. Remove _manager.onCameraMove and _manager.updateMap from GoogleMap
content = content.replace('            onCameraMove: _manager.onCameraMove,\n', '')
content = content.replace('            onCameraIdle: _manager.updateMap,\n', '')

with open('lib/screens/call_point_map_page.dart', 'w', encoding='utf-8') as f:
    f.write(content)
