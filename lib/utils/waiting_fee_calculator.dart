/// 업체별 대기시간 요금 계산(일지 저장·통계와 무관한 참고용).
class WaitingFeeCompany {
  const WaitingFeeCompany({
    required this.id,
    required this.name,
    required this.ruleSummary,
    required this.calculate,
  });

  final String id;
  final String name;
  final String ruleSummary;
  final int Function(int minutes) calculate;

  static const List<WaitingFeeCompany> all = [
    WaitingFeeCompany(
      id: 'gogo',
      name: '고고대리',
      ruleSummary: '10분 이후 1분당 300원 (예: 11분 3,300원)',
      calculate: _gogo,
    ),
    WaitingFeeCompany(
      id: 'handle_for_you',
      name: '핸들포유',
      ruleSummary: '10분 무료, 이후 10분당 4,000원',
      calculate: _handleForYou,
    ),
    WaitingFeeCompany(
      id: 'cheonsa',
      name: '천사대리',
      ruleSummary: '10분 무료, 35분 미만 6,000원 / 35분 이상 9,000원',
      calculate: _cheonsa,
    ),
    WaitingFeeCompany(
      id: 'kakao_premium',
      name: '카카오 프리미엄',
      ruleSummary: '15분 무료, 이후 10분당 3,000원',
      calculate: _kakaoPremium,
    ),
    WaitingFeeCompany(
      id: 'star',
      name: '스타',
      ruleSummary: '21분 5,000원 / 30분 7,500원 / 40분 초과 10,000원',
      calculate: _star,
    ),
    WaitingFeeCompany(
      id: 'jeil',
      name: '제일콜',
      ruleSummary: '20분 이상 5,000원 / 40분 이상 10,000원',
      calculate: _jeil,
    ),
    WaitingFeeCompany(
      id: 'cheongbang',
      name: '청방',
      ruleSummary: '21분 5,000원 / 41분 10,000원 / 61분 15,000원',
      calculate: _cheongbang,
    ),
    WaitingFeeCompany(
      id: 'hanaro',
      name: '하나로',
      ruleSummary: '25분부터 5,000원',
      calculate: _hanaro,
    ),
    WaitingFeeCompany(
      id: 'daerigo',
      name: '대리고',
      ruleSummary: '20~30분 5,000원, 30분 초과 10분당 2,000원 추가',
      calculate: _daerigo,
    ),
    WaitingFeeCompany(
      id: 'good_service',
      name: '굿서비스',
      ruleSummary: '25분 무료, 30분 이상 5,000원',
      calculate: _goodService,
    ),
    WaitingFeeCompany(
      id: 'general_corporate',
      name: '일반법인',
      ruleSummary: '10분 무료, 이후 30분당 5,000원',
      calculate: _generalCorporate,
    ),
  ];

  static WaitingFeeCompany? byId(String id) {
    for (final company in all) {
      if (company.id == id) return company;
    }
    return null;
  }

  static int calculateFor(String companyId, int minutes) {
    final company = byId(companyId);
    if (company == null) return 0;
    return company.calculate(_normalizeMinutes(minutes));
  }

  static int _normalizeMinutes(int minutes) {
    if (minutes < 0) return 0;
    return minutes;
  }

  static int _ceilDiv(int value, int divisor) {
    if (value <= 0) return 0;
    return (value + divisor - 1) ~/ divisor;
  }

  static int _gogo(int minutes) {
    if (minutes <= 10) return 0;
    return minutes * 300;
  }

  static int _handleForYou(int minutes) {
    if (minutes <= 10) return 0;
    return _ceilDiv(minutes - 10, 10) * 4000;
  }

  static int _cheonsa(int minutes) {
    if (minutes <= 10) return 0;
    if (minutes < 35) return 6000;
    return 9000;
  }

  static int _kakaoPremium(int minutes) {
    if (minutes <= 15) return 0;
    return _ceilDiv(minutes - 15, 10) * 3000;
  }

  static int _star(int minutes) {
    if (minutes > 40) return 10000;
    if (minutes >= 30) return 7500;
    if (minutes >= 21) return 5000;
    return 0;
  }

  static int _jeil(int minutes) {
    if (minutes >= 40) return 10000;
    if (minutes >= 20) return 5000;
    return 0;
  }

  static int _cheongbang(int minutes) {
    if (minutes >= 61) return 15000;
    if (minutes >= 41) return 10000;
    if (minutes >= 21) return 5000;
    return 0;
  }

  static int _hanaro(int minutes) {
    if (minutes >= 25) return 5000;
    return 0;
  }

  static int _daerigo(int minutes) {
    if (minutes < 20) return 0;
    if (minutes <= 30) return 5000;
    return 5000 + _ceilDiv(minutes - 30, 10) * 2000;
  }

  static int _goodService(int minutes) {
    if (minutes < 30) return 0;
    return 5000;
  }

  static int _generalCorporate(int minutes) {
    if (minutes <= 10) return 0;
    return _ceilDiv(minutes - 10, 30) * 5000;
  }
}
