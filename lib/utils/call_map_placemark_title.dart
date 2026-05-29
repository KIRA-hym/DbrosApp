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
  if (admin.endsWith('도')) {
    // 도 단위(경기도 등) — 도명 생략, 시/군만 반환 (구는 표시하지 않음)
    // → 호출부에서 동/읍/면을 붙여 "XX시 XX동" 형태로 조합됨
    final cityOrCounty = _firstSegmentEndingWith(
          [locality, subAdmin, pm.locality, pm.subAdministrativeArea],
          '시',
        ) ??
        _firstSegmentEndingWith(
          [locality, subAdmin, pm.locality, pm.subAdministrativeArea],
          '군',
        );
    if (cityOrCounty != null) return cityOrCounty;
    return locality.isNotEmpty ? locality : admin;
  }

  final parts = <String>[];

  if (admin.endsWith('광역시')) {
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
  final allText = [
    pm.name,
    pm.street,
    pm.subLocality,
    pm.thoroughfare,
    pm.locality,
    pm.subAdministrativeArea,
    pm.administrativeArea,
  ].where((s) => s != null && s!.isNotEmpty).join(' ');

  // 1차: 띄어쓰기 기반으로 정확한 동/읍/면 찾기
  final tokens = allText.split(RegExp(r'\s+'));
  for (final suffix in ['동', '읍', '면']) {
    for (final token in tokens) {
      if (token.endsWith(suffix) && token.length >= 2) {
        // 길이나 로로 끝나는 오탐지 제외
        if (!token.endsWith('길') && !token.endsWith('로')) {
          return token;
        }
      }
    }
  }

  // 2차: 가/리 찾기 (예: 종로1가, 승언리)
  for (final suffix in ['가', '리']) {
    for (final token in tokens) {
      if (token.endsWith(suffix) && token.length >= 2) {
        if (!token.endsWith('길') && !token.endsWith('로') && !token.endsWith('거리')) {
          return token;
        }
      }
    }
  }

  // 3차: 공백 없이 붙어있는 경우 정규식으로 강제 추출 (예: 신림동123-4)
  final match = RegExp(r'([가-힣a-zA-Z0-9]+[동읍면가리])(?:[\s\-0-9]|$)').firstMatch(allText);
  if (match != null) {
    final res = match.group(1)!;
    if (res.length >= 2 && !res.endsWith('길') && !res.endsWith('로') && !res.endsWith('거리')) {
      return res;
    }
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
