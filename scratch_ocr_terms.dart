import 'dart:io';

void main() {
  final files = [
    r'C:\dbros_app\lib\screens\write_log_page.dart',
  ];

  for (final path in files) {
    final file = File(path);
    if (!file.existsSync()) continue;
    
    var content = file.readAsStringSync();

    content = content.replaceAll(
      'OCR(자동 인식)',
      '콜카드 인식(자동 입력)'
    );
    
    content = content.replaceAll(
      'OCR(자동 인식) 이용 안내',
      '콜카드 인식(자동 입력) 이용 안내'
    );
    
    content = content.replaceAll(
      'OCR 기능은',
      '콜카드 인식 기능은'
    );
    
    content = content.replaceAll(
      '콜카드 이미지 자동 인식',
      '콜카드 인식(자동 입력)'
    );

    file.writeAsStringSync(content);
    print('Updated ' + path);
  }
}
