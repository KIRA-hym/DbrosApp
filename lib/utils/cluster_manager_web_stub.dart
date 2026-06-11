library cluster_manager_web_stub;

import 'maps_web_stub.dart';

mixin ClusterItem {
  LatLng get location => const LatLng(0, 0);
}

class Cluster<T extends ClusterItem> {
  final LatLng location = const LatLng(0, 0);
  final Iterable<T> items = const [];
  final bool isMultiple = false;
  final int count = 0;
  String getId() => '';
}

class ClusterManager<T extends ClusterItem> {
  ClusterManager(
    Iterable<T> items,
    void Function(Set<Marker>) updateMarkers, {
    required Future<Marker> Function(Cluster<T>) markerBuilder,
    double stopClusteringZoom = 15.0,
  });

  Future<void> setMapId(int mapId) async {}
  void setItems(List<T> items) {}
  void onCameraMove(CameraPosition position) {}
  void updateMap() {}
}
