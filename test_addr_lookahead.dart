void main() {
  String flat2 = '경기 화성시 병점구 진안동 별하나라이브 경기 안산시 단원구 신길동 신길고등학교 32,000P';
  final addrRegex = RegExp(r'(\uC11C\uC6B8|\uBD80\uC0B0|\uB300\uAD6C|\uC778\uCC9C|\uAD11\uC8FC|\uB300\uC804|\uC6B8\uC0B0|\uC138\uC885|\uACBD\uAE30|\uAC15\uC6D0|\uCDA9\uBD81|\uCDA9\uB0A8|\uC804\uBD81|\uC804\uB0A8|\uACBD\uBD81|\uACBD\uB0A8|\uC81C\uC8FC)\s+[\uAC00-\uD7A3]+\s*(?:\uC2DC|\uAD70|\uAD6C)\s+(?:(?!\uC11C\uC6B8|\uBD80\uC0B0|\uB300\uAD6C|\uC778\uCC9C|\uAD11\uC8FC|\uB300\uC804|\uC6B8\uC0B0|\uC138\uC885|\uACBD\uAE30|\uAC15\uC6D0|\uCDA9\uBD81|\uCDA9\uB0A8|\uC804\uBD81|\uC804\uB0A8|\uACBD\uBD81|\uACBD\uB0A8|\uC81C\uC8FC)[^\uB3C4\uCC29\uC2E4\uC218\uC775\n])*');
  final matches = addrRegex.allMatches(flat2).toList();
  for (var m in matches) {
      print('ADDR: ' + m.group(0)!.trim());
  }
}