import 'dart:convert';
import 'dart:io';

import 'package:dbros_app/ocr_lab/plain_ocr_parse_lab.dart';
import 'package:dbros_app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PC 웹 실험실 백엔드. [tools/serve_ocr_parse_lab.ps1] 가 환경변수를 넣고 이 테스트만 실행합니다.
void main() {
  final bridgeOnly = Platform.environment['OCR_LAB_INPUT_PATH'];

  test(
    'OCR_lab_bridge',
    () async {
      final inPath = Platform.environment['OCR_LAB_INPUT_PATH'];
      final outPath = Platform.environment['OCR_LAB_OUTPUT_PATH'];
      if (inPath == null || outPath == null) {
        fail('OCR_LAB_INPUT_PATH / OCR_LAB_OUTPUT_PATH required');
      }

      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({
        'baseFeeRate': 20.0,
        'insuranceType': 'none',
      });
      await SettingsService.init();

      final inputJson = jsonDecode(File(inPath).readAsStringSync()) as Map<String, dynamic>;
      final text = inputJson['text']?.toString() ?? '';
      final forced = inputJson['forcedProgram']?.toString();

      final result = PlainOcrParseLab.parse(text, forcedProgramLabel: forced);
      File(outPath).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(result),
      );
    },
    skip: bridgeOnly == null ? 'lab bridge only (set OCR_LAB_INPUT_PATH)' : false,
  );
}
