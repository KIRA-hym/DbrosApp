import 'dart:io';

void main() {
  final file = File(r'C:\dbros_app\lib\screens\write_log_page.dart');
  var content = file.readAsStringSync();

  // 1. Add _hasOcrWarning variable
  if (!content.contains('bool _hasOcrWarning')) {
    content = content.replaceFirst('  int? _logId;', '  bool _hasOcrWarning = false;\n  int? _logId;');
  }

  // 2. Update the missing logic
  content = content.replaceAll(
    'bool get _isStartLocMissing => _logId != null && _startLocCon.text.trim().isEmpty;', 
    'bool get _isStartLocMissing => (_logId != null || _hasOcrWarning) && _startLocCon.text.trim().isEmpty;'
  );
  content = content.replaceAll(
    'bool get _isEndLocMissing => _logId != null && _endLocCon.text.trim().isEmpty;', 
    'bool get _isEndLocMissing => (_logId != null || _hasOcrWarning) && _endLocCon.text.trim().isEmpty;'
  );
  content = content.replaceAll(
    'bool get _isIncomeMissing => _logId != null && _parseMoney(_incomeCon.text) <= 0;', 
    'bool get _isIncomeMissing => (_logId != null || _hasOcrWarning) && _parseMoney(_incomeCon.text) <= 0;'
  );

  // 3. Update _buildOcrWarningBanner
  final oldBannerRegex = RegExp(r'Widget _buildOcrWarningBanner\(\)\s*\{[\s\S]*?return Container\([\s\S]*?\}\s*\}\s*Widget _buildFormLayout');
  final newBanner = '''Widget _buildOcrWarningBanner() {
    if (!_hasOcrWarning) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "콜카드 인식 결과, 일부 정보를 자동으로 가져오지 못했습니다. 빨간색으로 표시된 항목을 확인 후 직접 입력해 주세요.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormLayout''';
  content = content.replaceAll(oldBannerRegex, newBanner);

  // 4. Update _detectProgramAndParse
  final endOfDetectRegex = RegExp(r'setState\(\(\)\s*\{\s*_selectedProgram\s*=\s*_coerceProgramForSelection\(detected\);\s*\}\);\s*_resolveStartCoords\(\);\s*_resolveEndCoords\(\);');
  final newEndOfDetect = '''setState(() {
      _selectedProgram = _coerceProgramForSelection(detected);
    });

    _resolveStartCoords();
    _resolveEndCoords();
    
    setState(() {
      _hasOcrWarning = _startLocCon.text.trim().isEmpty || _endLocCon.text.trim().isEmpty || _parseMoney(_incomeCon.text) <= 0;
    });''';
  content = content.replaceAll(endOfDetectRegex, newEndOfDetect);

  file.writeAsStringSync(content);
  print('Done applying dynamic OCR warning banner.');
}
