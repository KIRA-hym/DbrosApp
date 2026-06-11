import 'dart:io';

void main() {
  final file = File('lib/utils/logi_colmanner_ocr.dart');
  var content = file.readAsStringSync();

  // 1. Raw string 보간 오류 수정
  content = content.replaceAll(
    r"r'^${RemoteConfigService().regionPattern}'",
    r"('^' + RemoteConfigService().regionPattern)",
  );
  content = content.replaceAll(
    r"r'^${RemoteConfigService().regionPattern}(?=\s)'",
    r"('^' + RemoteConfigService().regionPattern + r'(?=\s)')",
  );
  content = content.replaceAll(
    r"r'^${RemoteConfigService().regionPattern}\s+([가-힣\d]+(?:시|군|구|도)?)'",
    r"('^' + RemoteConfigService().regionPattern + r'\s+([가-힣\d]+(?:시|군|구|도)?)')",
  );
  content = content.replaceAll(
    r"r'([가-힣0-9\)\]\}\.])${RemoteConfigService().regionPattern}(?=\s)'",
    r"(r'([가-힣0-9\)\]\}\.])' + RemoteConfigService().regionPattern + r'(?=\s)')",
  );
  content = content.replaceAll(
    r"r'^${RemoteConfigService().regionPattern}([가-힣])'",
    r"('^' + RemoteConfigService().regionPattern + r'([가-힣])')",
  );
  content = content.replaceAll(
    r"r'\s${RemoteConfigService().regionPattern}\s+'",
    r"(r'\s' + RemoteConfigService().regionPattern + r'\s+')",
  );
  content = content.replaceAll(
    r"r'(?:^|\s)${RemoteConfigService().regionPattern}'",
    r"(r'(?:^|\s)' + RemoteConfigService().regionPattern)",
  );

  // 2. _looksLikeDestinationLead 에서 text.trim() 과 노이즈 제거 추가
  content = content.replaceAll(
    '''  static bool _looksLikeDestinationLead(String line) {
    if (RegExp(''',
    '''  static bool _looksLikeDestinationLead(String line) {
    var text = line.trim();
    text = text.replaceFirst(RegExp(r'^(?:[ⓓⓐⓑ]?법\\]?)'), '').trim();
    if (RegExp('''
  );
  
  content = content.replaceAll(
    ''').hasMatch(line)) {
      return true;
    }
    return RegExp(r'^[가-힣]+(시|군|구)').hasMatch(line);
  }''',
    ''').hasMatch(text)) {
      return true;
    }
    return RegExp(r'^[가-힣]{2,4}(시|군|구)').hasMatch(text);
  }'''
  );

  // 3. _parseColmannerLocationsLegacy 에서 between.isEmpty 조건 해제 및 무조건 partition 호출
  final oldLegacyBlock = '''    if (_shouldSplitColmannerBetweenTail(between)) {
      startParts.addAll(between.sublist(0, between.length - 1));
      endParts.add(between.last);
      if (endLead.isNotEmpty &&
          !_isCustomerMetaLine(endLead) &&
          !_isOrphanCustomerNumber(endLead)) {
        endParts.add(endLead);
      }
      endParts.addAll(afterEnd);
    } else {
      startParts.addAll(between);
      if (endLead.isNotEmpty &&
          !_isCustomerMetaLine(endLead) &&
          !_isOrphanCustomerNumber(endLead)) {
        endParts.add(endLead);
      }
      if (afterEnd.isNotEmpty) {
        if (between.isEmpty) {
          final partitioned = _partitionColmannerAfterEnd(
            afterEnd,
            destinationLead: endLead,
          );
          startParts.addAll(partitioned.departure);
          endParts.addAll(partitioned.destination);
        } else {
          endParts.addAll(afterEnd);
        }
      }
    }''';

  final newLegacyBlock = '''    if (_shouldSplitColmannerBetweenTail(between)) {
      startParts.addAll(between.sublist(0, between.length - 1));
      endParts.add(between.last);
      if (endLead.isNotEmpty &&
          !_isCustomerMetaLine(endLead) &&
          !_isOrphanCustomerNumber(endLead)) {
        endParts.add(endLead);
      }
      if (afterEnd.isNotEmpty) {
        final partitioned = _partitionColmannerAfterEnd(
          afterEnd,
          destinationLead: endParts.isNotEmpty ? endParts.last : endLead,
        );
        startParts.addAll(partitioned.departure);
        endParts.addAll(partitioned.destination);
      }
    } else {
      startParts.addAll(between);
      if (endLead.isNotEmpty &&
          !_isCustomerMetaLine(endLead) &&
          !_isOrphanCustomerNumber(endLead)) {
        endParts.add(endLead);
      }
      if (afterEnd.isNotEmpty) {
        final partitioned = _partitionColmannerAfterEnd(
          afterEnd,
          destinationLead: endLead,
        );
        startParts.addAll(partitioned.departure);
        endParts.addAll(partitioned.destination);
      }
    }''';

  content = content.replaceFirst(oldLegacyBlock, newLegacyBlock);

  file.writeAsStringSync(content);
  print('Done.');
}
