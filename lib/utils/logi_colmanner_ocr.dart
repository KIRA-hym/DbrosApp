// GEMINI_HYBRID_PARSE_BEGIN
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

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

  static Future<PartnerCallParsed> parseLogi(String fullText, {List<TextBlock>? blocks}) async {
    final r = await GeminiApiService.instance.parseCallCard(
      fullText: fullText,
      detectedProgram: '로지',
    );
    return _map(r);
  }

  static Future<PartnerCallParsed> parseColmanner(String fullText, {List<TextBlock>? blocks}) async {
    final r = await GeminiApiService.instance.parseCallCard(
      fullText: fullText,
      detectedProgram: '콜마너',
    );
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
