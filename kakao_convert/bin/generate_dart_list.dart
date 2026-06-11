import 'dart:convert';
import 'dart:io';
import 'package:proj4dart/proj4dart.dart';

void main() async {
  final projStr = '+proj=tmerc +lat_0=38 +lon_0=127 +k=1 +x_0=200000 +y_0=500000 +ellps=bessel +units=m +no_defs +towgs84=-115.80,474.99,674.11,1.16,-2.31,-1.63,6.43';
  final epsg5181 = Projection.add('EPSG:5181', projStr);
  final wgs84 = Projection.get('EPSG:4326')!;

  final files = [
    {'path': '../kakao.json', 'type': 'reference'},
    {'path': '../kakao2.json', 'type': 'restroom'},
    {'path': '../kakao3.json', 'type': 'shuttle'},
  ];

  final outFile = File('../lib/data/default_call_points.dart');
  final sink = outFile.openWrite();

  sink.writeln("final List<Map<String, dynamic>> defaultCallPoints = [");

  for (var fileInfo in files) {
    final inputFile = File(fileInfo['path']!);
    if (!await inputFile.exists()) continue;

    final content = await inputFile.readAsString();
    final data = jsonDecode(content);
    final favorites = data['favorites'] as List<dynamic>;

    for (var item in favorites) {
      double lat = 0.0;
      double lng = 0.0;
      
      if (item.containsKey('lat') && item.containsKey('lon')) {
        lat = double.parse(item['lat'].toString());
        lng = double.parse(item['lon'].toString());
      } else if (item.containsKey('x') && item.containsKey('y')) {
        final x = double.parse(item['x'].toString()) / 2.5;
        final y = double.parse(item['y'].toString()) / 2.5;
        final point = Point(x: x, y: y);
        final converted = epsg5181.transform(wgs84, point);
        lat = converted.y;
        lng = converted.x;
      } else {
        continue;
      }

      final String display1 = item['display1']?.toString() ?? '';
      final String display2 = item['display2']?.toString() ?? '';
      final String memo = item['memo']?.toString() ?? '';
      final String locationName = display2.isEmpty ? display1 : '$display1 ($display2)';

      String escapeDart(String input) {
        return input.replaceAll("'", "\\'").replaceAll('\n', ' ');
      }

      sink.writeln("  {");
      sink.writeln("    'start_lat': $lat,");
      sink.writeln("    'start_lng': $lng,");
      sink.writeln("    'start_location': '${escapeDart(locationName)}',");
      sink.writeln("    'type': '${fileInfo['type']}',");
      sink.writeln("    'memo': '${escapeDart(memo)}',");
      sink.writeln("    'user_id': 'admin',");
      sink.writeln("  },");
    }
  }

  sink.writeln("];");
  await sink.flush();
  await sink.close();
  print('Generated lib/data/default_call_points.dart');
}
