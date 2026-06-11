import 'dart:convert';
import 'dart:io';
import 'package:proj4dart/proj4dart.dart';

void main(List<String> args) async {
  // Kakao WCONGNAMUL is exactly EPSG:5181 multiplied by 2.5
  final String projStr = '+proj=tmerc +lat_0=38 +lon_0=127 +k=1 +x_0=200000 +y_0=500000 +ellps=bessel +units=m +no_defs +towgs84=-115.80,474.99,674.11,1.16,-2.31,-1.63,6.43';
  final epsg5181 = Projection.add('EPSG:5181', projStr);
  final wgs84 = Projection.get('EPSG:4326')!;

  if (args.length < 3) {
    print('Usage: dart run bin/kakao_convert.dart <input_json> <output_csv> <type_string>');
    return;
  }

  final inputPath = args[0];
  final outputPath = args[1];
  final typeString = args[2];

  final inputFile = File(inputPath);
  if (!await inputFile.exists()) {
    print('Input file not found: $inputPath');
    return;
  }

  final content = await inputFile.readAsString();
  final data = jsonDecode(content);
  final favorites = data['favorites'] as List<dynamic>;

  final outputFile = File(outputPath);
  final sink = outputFile.openWrite();
  
  // CSV Header
  // timestamp, user_id, lat, lng, type, drive_time, program, start_location, waypoint, end_location, gross_fare, memo
  sink.writeln('timestamp,user_id,lat,lng,type,drive_time,program,start_location,waypoint,end_location,gross_fare,memo');

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
      continue; // No coordinates
    }

    // Replace commas and quotes in text fields
    String escapeCsv(String input) {
      if (input.contains(',') || input.contains('"')) {
        return '"' + input.replaceAll('"', '""') + '"';
      }
      return input;
    }

    final String display1 = item['display1']?.toString() ?? '';
    final String display2 = item['display2']?.toString() ?? '';
    final String memo = item['memo']?.toString() ?? '';
    
    // Combine display1 and display2 if both exist, otherwise use display1
    final String locationName = display2.isEmpty ? display1 : '$display1 ($display2)';
    
    final String timestamp = item['created_at']?.toString() ?? DateTime.now().toIso8601String();
    
    sink.writeln('$timestamp,admin,$lat,$lng,$typeString,,,"${escapeCsv(locationName)}",,,0,"${escapeCsv(memo)}"');
  }

  await sink.flush();
  await sink.close();
  
  print('Conversion complete! Checked: $outputPath');
}
