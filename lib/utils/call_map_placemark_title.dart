import 'package:geocoding/geocoding.dart';

/// 역지오코딩 [Placemark] → 콜맵 AppBar (1줄: 시·구/도·시, 2줄: 동·읍·면명).
(String line1, String localityName) callMapTitlesFromPlacemark(Placemark pm) {
  final admin = (pm.administrativeArea ?? '').trim();
  final locality = (pm.locality ?? '').trim();
  final subAdmin = (pm.subAdministrativeArea ?? '').trim();

  final dong = _localityLine2Name(pm);

  if (_isSeoul(admin, locality)) {
    final gu = _firstSegmentEndingWith(
      [pm.subLocality, pm.locality, pm.subAdministrativeArea, pm.name],
      '구',
    );
    final parts = <String>[];
    if (gu != null) parts.add(gu);
    if (dong.isNotEmpty) parts.add(dong);
    
    final line1 = parts.isNotEmpty ? parts.join(' ') : '서울시';
    return (line1, '');
  }

  final line1 = _provinceAndCityLine(admin, locality, subAdmin, pm);
  return (line1, dong);
}

bool _isSeoul(String admin, String locality) =>
    admin.contains('서울') || locality.contains('서울');

String _provinceAndCityLine(
  String admin,
  String locality,
  String subAdmin,
  Placemark pm,
) {
  final parts = <String>[];

  if (admin.endsWith('도')) {
    // 도 단위(경기도 등)는 생략
  } else if (admin.endsWith('광역시')) {
    parts.add(admin.replaceFirst('광역시', '시'));
    final gu = _firstSegmentEndingWith(
      [pm.subLocality, pm.locality, pm.subAdministrativeArea],
      '구',
    );
    if (gu != null) {
      return '${parts.first} $gu';
    }
    return parts.first;
  } else if (admin.isNotEmpty && !admin.contains('서울')) {
    // 세종특별자치시, 제주특별자치도 등 기타 지역
    parts.add(admin);
  }

  final cityOrCounty = _firstSegmentEndingWith(
    [locality, subAdmin, pm.locality, pm.subAdministrativeArea],
    '시',
  ) ??
      _firstSegmentEndingWith(
        [locality, subAdmin, pm.locality, pm.subAdministrativeArea],
        '군',
      );
  if (cityOrCounty != null &&
      !parts.any((p) => p == cityOrCounty || p.contains(cityOrCounty))) {
    parts.add(cityOrCounty);
  }

  final gu = _firstSegmentEndingWith(
    [subAdmin, pm.subLocality, pm.locality, pm.subAdministrativeArea],
    '구',
  );
  if (gu != null && !parts.any((p) => p == gu || p.endsWith(gu))) {
    parts.add(gu);
  }

  if (parts.isNotEmpty) return parts.join(' ');
  if (locality.isNotEmpty) return locality;
  return admin;
}

String _localityLine2Name(Placemark pm) {
  const suffixes = ['동', '읍', '면'];
  final fields = [pm.subLocality, pm.thoroughfare, pm.name, pm.street];
  for (final suffix in suffixes) {
    final found = _firstSegmentEndingWith(fields, suffix);
    if (found != null) return found;
  }
  return '';
}

String? _firstSegmentEndingWith(List<String?> fields, String suffix) {
  for (final raw in fields) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) continue;
    for (final seg in text.split(RegExp(r'\s+'))) {
      if (seg.endsWith(suffix)) return seg;
    }
  }
  return null;
}
