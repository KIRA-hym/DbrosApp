// 멀티모달 올인원 파이프 검증 (일일 사용 카운트 1회 증가).
// 사용: 프로젝트 루트에서
//   dart run tool/gemini_smoke_test.dart <콜카드.jpg>
// 또는 GEMINI_SMOKE_IMAGE 환경 변수에 경로 설정.
// 키: defines.local.json / GEMINI_API_KEY / --dart-define (GeminiApiService 와 동일)

import 'dart:io';

import 'package:dbros_app/services/gemini_api_service.dart';

Future<void> main(List<String> args) async {
  final path = args.isNotEmpty
      ? args[0].trim()
      : (Platform.environment['GEMINI_SMOKE_IMAGE']?.trim() ?? '');
  if (path.isEmpty) {
    stderr.writeln(
      '콜카드 이미지 경로가 필요합니다.\n'
      '  dart run tool/gemini_smoke_test.dart <이미지.jpg>\n'
      r'  또는 PowerShell: $env:GEMINI_SMOKE_IMAGE = "경로" ; dart run tool/gemini_smoke_test.dart',
    );
    exitCode = 1;
    return;
  }
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('파일을 찾을 수 없습니다: $path');
    exitCode = 1;
    return;
  }

  final sw = Stopwatch()..start();
  final r = await GeminiApiService.instance.parseCallCardImage(file);
  sw.stop();
  if (r.usageExceeded) {
    stderr.writeln('일일 콜카드 인식 한도 초과');
    exitCode = 1;
    return;
  }
  if (r.fields == null) {
    stderr.writeln(r.errorMessage ?? '실패');
    exitCode = 1;
    return;
  }
  final f = r.fields!;
  stdout.writeln('elapsed_ms=${sw.elapsedMilliseconds}');
  stdout.writeln('program=${f.program} grossFare=${f.grossFare} driveTime=${f.driveTimeHm}');
  stdout.writeln('start=${f.startLocation}');
  stdout.writeln('waypoint=${f.waypoint}');
  stdout.writeln('end=${f.endLocation}');
}
