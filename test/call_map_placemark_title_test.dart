import 'package:dbros_app/utils/call_map_placemark_title.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';

void main() {
  test('서울: 서울시 + 구, 동', () {
    final (line1, dong) = callMapTitlesFromPlacemark(
      Placemark(
        administrativeArea: '서울특별시',
        locality: '강서구',
        subLocality: '화곡동',
      ),
    );
    expect(line1, '서울시 강서구');
    expect(dong, '화곡동');
  });

  test('부천: 경기도 + 시 + 구, 동', () {
    final (line1, dong) = callMapTitlesFromPlacemark(
      Placemark(
        administrativeArea: '경기도',
        locality: '부천시',
        subAdministrativeArea: '오정구',
        subLocality: '여월동',
      ),
    );
    expect(line1, '경기도 부천시 오정구');
    expect(dong, '여월동');
  });

  test('경기: 경기도 + 시, 동', () {
    final (line1, dong) = callMapTitlesFromPlacemark(
      Placemark(
        administrativeArea: '경기도',
        locality: '부천시',
        subLocality: '중동',
      ),
    );
    expect(line1, '경기도 부천시');
    expect(dong, '중동');
  });

  test('충남: 충청남도 + 시, 면', () {
    final (line1, locality) = callMapTitlesFromPlacemark(
      Placemark(
        administrativeArea: '충청남도',
        locality: '아산시',
        subLocality: '둔포면',
      ),
    );
    expect(line1, '충청남도 아산시');
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
    expect(line1, '충청북도 음성군');
    expect(locality, '금왕읍');
  });
}
