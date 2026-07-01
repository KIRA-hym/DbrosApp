/// 웹 환경에서 google_maps_flutter 대신 사용하는 스텁(stub).
/// 지도 기능은 웹에서 비활성화되므로 빈 클래스만 제공합니다.

library maps_web_stub;

import 'dart:typed_data';
import 'package:flutter/widgets.dart';

// 기본 좌표
class LatLng {
  const LatLng(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class LatLngBounds {
  const LatLngBounds({required this.southwest, required this.northeast});
  final LatLng southwest;
  final LatLng northeast;
}

class BitmapDescriptor {
  const BitmapDescriptor._();
  static const BitmapDescriptor defaultMarker = BitmapDescriptor._();
  static BitmapDescriptor defaultMarkerWithHue(double hue) => BitmapDescriptor._();
  static BitmapDescriptor fromBytes(Uint8List byteData) => BitmapDescriptor._();
  static const double hueGreen = 120.0;
  static const double hueOrange = 30.0;
  static const double hueRed = 0.0;
  static const double hueAzure = 210.0;
}

class CameraUpdate {
  const CameraUpdate._();
  static CameraUpdate newLatLngZoom(LatLng target, double zoom) => CameraUpdate._();
  static CameraUpdate newLatLngBounds(LatLngBounds bounds, double padding) => CameraUpdate._();
}

class CameraPosition {
  const CameraPosition({required this.target, this.zoom = 12.0});
  final LatLng target;
  final double zoom;
}

class MarkerId {
  const MarkerId(this.value);
  final String value;
}

class InfoWindow {
  const InfoWindow({this.title, this.snippet});
  static const InfoWindow noText = InfoWindow();
  final String? title;
  final String? snippet;
}

class Marker {
  const Marker({
    required this.markerId,
    this.position = const LatLng(0, 0),
    this.infoWindow = InfoWindow.noText,
    this.icon,
    this.anchor = const Offset(0.5, 1.0),
    this.draggable = false,
    this.onDragEnd,
    this.onTap,
    this.zIndex = 0.0,
  });
  final MarkerId markerId;
  final LatLng position;
  final InfoWindow infoWindow;
  final BitmapDescriptor? icon;
  final Offset anchor;
  final bool draggable;
  final void Function(LatLng)? onDragEnd;
  final VoidCallback? onTap;
  final double zIndex;
}

class PolylineId {
  const PolylineId(this.value);
  final String value;
}

class Polyline {
  const Polyline({
    required this.polylineId,
    this.points = const [],
    this.color,
    this.width = 3,
  });
  final PolylineId polylineId;
  final List<LatLng> points;
  final Object? color;
  final int width;
}

class GoogleMapController {
  int get mapId => 0;
  Future<void> animateCamera(CameraUpdate update) async {}
  Future<double> getZoomLevel() async => 15.0;
  Future<void> showMarkerInfoWindow(MarkerId markerId) async {}
}

class GoogleMap extends StatelessWidget {
  const GoogleMap({
    required this.initialCameraPosition,
    this.markers,
    this.polylines,
    this.onMapCreated,
    this.myLocationEnabled,
    this.myLocationButtonEnabled,
    this.zoomControlsEnabled,
    this.mapToolbarEnabled,
    this.onTap,
    this.onCameraMove,
    this.onCameraIdle,
    this.compassEnabled,
    this.padding = EdgeInsets.zero,
  });

  final CameraPosition initialCameraPosition;
  final Set<Marker>? markers;
  final Set<Polyline>? polylines;
  final void Function(GoogleMapController)? onMapCreated;
  final bool? myLocationEnabled;
  final bool? myLocationButtonEnabled;
  final bool? zoomControlsEnabled;
  final bool? mapToolbarEnabled;
  final void Function(LatLng)? onTap;
  final void Function(CameraPosition)? onCameraMove;
  final VoidCallback? onCameraIdle;
  final bool? compassEnabled;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
