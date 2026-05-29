import 'package:dbros_app/utils/call_map_placemark_title.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';

void main() {
  test('서울: 구 + 동 (한 줄)', () {
    final (line1, dong) = callMapTitlesFromPlacemark(
      Placemark(
        administrativeArea: '서울특별시',
        locality: '강서구',
        subLocality: '화곡동',
      ),
    );
    expect(line1, '강서구 화곡동');
    expect(dong, '');
  });

  test('서울: 강서구 염창동', () {
    final (line1, dong) = callMapTitlesFromPlacemark(
      Placemark(
        administrativeArea: '서울특별시',
        locality: '강서구',
        subLocality: '염창동',
      ),
    );
    expect(line1, '강서구 염창동');
    expect(dong, '');
  });

  test('서울: 동명이 locality에만 있는 경우', () {
    final (line1, dong) = callMapTitlesFromPlacemark(
      Placemark(
        administrativeArea: '서울특별시',
        subAdministrativeArea: '강서구',
        locality: '염창동',
      ),
    );
    expect(line1, '강서구 염창동');
    expect(dong, '');
  });

  test('부천: 시 + 구, 동', () {
    final (line1, dong) = callMapTitlesFromPlacemark(
      Placemark(
        administrativeArea: '경기도',
        locality: '부천시',
        subAdministrativeArea: '오정구',
        subLocality: '여월동',
      ),
    );
    expect(line1, '부천시');
    expect(dong, '여월동');
  });

  test('경기: 시, 동', () {
    final (line1, dong) = callMapTitlesFromPlacemark(
      Placemark(
        administrativeArea: '경기도',
        locality: '부천시',
        subLocality: '중동',
      ),
    );
    expect(line1, '부천시');
    expect(dong, '중동');
  });

  test('충남: 시, 면', () {
    final (line1, locality) = callMapTitlesFromPlacemark(
      Placemark(
        administrativeArea: '충청남도',
        locality: '아산시',
        subLocality: '둔포면',
      ),
    );
    expect(line1, '아산시');
    expect(locality, '둔포면');
  });

  test('충북: 읍 단위', () {
    final (line1, locality) = callMapTitlesFromPlacemark(
      Placemark(
        administrativeArea: '충청북도',
        locality: '음성군',
        subLocality: '금왕읍',
      ),
    );
    expect(line1, '음성군');
    expect(locality, '금왕읍');
  });
}
