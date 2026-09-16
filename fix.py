
with open('lib/services/call_card_ocr_parse_service.dart', 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace('import \'smart_ocr_service.dart\'; // 신규 추가', '')
c = c.replace('return await SmartOcrService.enhance(logData, recognizedText.text);', 'return logData;')
with open('lib/services/call_card_ocr_parse_service.dart', 'w', encoding='utf-8') as f:
    f.write(c)

