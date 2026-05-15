// GEMINI_HYBRID_PARSE_BEGIN
import 'dart:io';

import '../services/gemini_api_service.dart';
import 'drive_time_format.dart';

class PartnerCallParsed {
  final String driveTimeHm;
  final int grossFare;
  final String startLocation;
  final String endLocation;
  final String waypoint;

  const PartnerCallParsed({
    required this.driveTimeHm,
    required this.grossFare,
    required this.startLocation,
    required this.endLocation,
    required this.waypoint,
  });
}

class LogiColmannerOcr {
  LogiColmannerOcr._();

  static Future<PartnerCallParsed> parseLogi(File imageFile) async {
    final r = await GeminiApiService.instance.parseCallCardImage(imageFile);
    return _map(r);
  }

  static Future<PartnerCallParsed> parseColmanner(File imageFile) async {
    final r = await GeminiApiService.instance.parseCallCardImage(imageFile);
    return _map(r);
  }

  static PartnerCallParsed _map(GeminiParseResult r) {
    if (r.usageExceeded || r.fields == null) {
      return const PartnerCallParsed(
        driveTimeHm: '',
        grossFare: 0,
        startLocation: '',
        endLocation: '',
        waypoint: '',
      );
    }
    final f = r.fields!;
    final time = f.driveTimeHm.isEmpty
        ? ''
        : (normalizeDriveTimeHm(f.driveTimeHm) ?? f.driveTimeHm);
    return PartnerCallParsed(
      driveTimeHm: time,
      grossFare: f.grossFare,
      startLocation: f.startLocation,
      endLocation: f.endLocation,
      waypoint: f.waypoint,
    );
  }
}
// GEMINI_HYBRID_PARSE_END
