/// [normalizeDriveTimeHm] 기준으로 저장 가능한 운행시간이면 true (OCR 인식 성공 등).
bool hasValidDriveTimeHm(Object? raw) => normalizeDriveTimeHm(raw?.toString()) != null;

/// 로컬 [DateTime]을 저장용 `HH:mm`으로 포맷합니다.
String formatDriveTimeHm(DateTime dt) {
  return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

/// OCR/입력 문자열을 저장·표시용 `HH:mm`(24시간)으로 통일합니다.
/// 예: `9:35` → `09:35`, `9:5` → `09:05`.
String? normalizeDriveTimeHm(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final s = raw.trim().replaceAll('：', ':').replaceAll('.', ':');
  final m = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(s);
  if (m == null) return null;
  final h = int.tryParse(m.group(1)!);
  final min = int.tryParse(m.group(2)!);
  if (h == null || min == null) return null;
  if (h < 0 || h > 23 || min < 0 || min > 59) return null;
  return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
}

/// 일지 저장 시 항상 유효한 `HH:mm`. 정규화 가능하면 [normalizeDriveTimeHm] 적용, 아니면 [fallback] 또는 현재 시각.
String resolveDriveTimeForStorage(String? raw, {DateTime? fallback}) {
  final n = normalizeDriveTimeHm(raw?.toString());
  if (n != null) return n;
  final fb = fallback ?? DateTime.now();
  return formatDriveTimeHm(fb);
}
