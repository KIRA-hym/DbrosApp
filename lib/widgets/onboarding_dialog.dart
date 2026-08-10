import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/settings_service.dart';

class OnboardingDialog extends StatefulWidget {
  const OnboardingDialog({super.key});

  static Future<void> showIfNeeded(BuildContext context) async {
    if (!SettingsService.hasSeenOnboarding) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const OnboardingDialog(),
      );
    }
  }

  @override
  State<OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<OnboardingDialog> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  final List<_OnboardingPageData> _pages = [
    _OnboardingPageData(
      title: '스마트한 일지 작성',
      description: '꼼꼼한 수기 일지입력은 기본!\n콜카드 이미지를 올리기만 하면\n자동으로 일지등록 완료!',
    ),
    _OnboardingPageData(
      title: '콜카드 다중 등록과 공유 기능',
      description: '하루 종일 쌓인 콜카드?\n앨범에서 여러 장을 선택해 한 번에 등록하세요!\n\n작성된 일지와 수익은 동료들과\n쉽게 공유할 수 있습니다.',
    ),
    _OnboardingPageData(
      title: '[프리미엄] 운전 중엔 캡처만!',
      description: '콜을 잡고 캡처하는 즉시\n백그라운드에서 자동으로 일지를 기록합니다.',
      warningText: '⚠️ 이미지 인식 특성상 단말기의 해상도와 폰트 영향으로 오입력될 수도 있어서 자동등록된 일지는 다시 검토해 주세요.',
    ),
    _OnboardingPageData(
      title: '완벽한 데이터 분석',
      description: '앱을 켜지 않아도 알림바에서\n순익과 근무시간을 실시간 확인하세요!\n\n상세 통계는 물론 콜맵(지도)에서\n운행 경로까지 한눈에 분석해 드립니다.',
    ),
    _OnboardingPageData(
      title: '나만을 위한 맞춤 설정',
      description: '글씨가 작아서 불편하셨나요?\n[설정] 탭에서 내 눈에 딱 맞게\n폰트 크기를 조절해 보세요.\n\n모든 자동화 기능도 입맛대로 켤 수 있습니다!',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentIndex < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  void _finishOnboarding() async {
    await SettingsService.setHasSeenOnboarding(true);
    await SettingsService.setHasAgreedPermissionsDisclosure(true);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // 목업과 100% 동일한 SVG 그래픽 문자열
  static const List<String> _svgGraphics = [
    // Slide 1
    '''<svg viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
      <defs>
          <linearGradient id="grad1" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" style="stop-color:#FFC107;stop-opacity:1" />
              <stop offset="100%" style="stop-color:#FF8F00;stop-opacity:1" />
          </linearGradient>
      </defs>
      <rect x="50" y="30" width="100" height="150" rx="15" fill="#333333" stroke="#555555" stroke-width="4"/>
      <rect x="55" y="40" width="90" height="130" rx="8" fill="#111111"/>
      <path d="M 65 20 L 135 20 L 135 90 L 65 90 Z" fill="#ffffff" opacity="0.9"/>
      <line x1="75" y1="40" x2="125" y2="40" stroke="#cccccc" stroke-width="4" stroke-linecap="round"/>
      <line x1="75" y1="55" x2="110" y2="55" stroke="#cccccc" stroke-width="4" stroke-linecap="round"/>
      <line x1="55" y1="75" x2="145" y2="75" stroke="#FFC107" stroke-width="3"/>
      <circle cx="100" cy="120" r="20" fill="url(#grad1)"/>
      <path d="M 90 120 L 98 128 L 110 110" stroke="#ffffff" stroke-width="4" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>''',
    // Slide 2
    '''<svg viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
      <rect x="60" y="30" width="80" height="100" rx="10" fill="#444444" transform="rotate(15 100 80)"/>
      <rect x="50" y="40" width="80" height="100" rx="10" fill="#666666" transform="rotate(-10 90 90)"/>
      <rect x="40" y="50" width="80" height="100" rx="10" fill="#ffffff"/>
      <circle cx="80" cy="90" r="15" fill="#FFC107"/>
      <line x1="55" y1="120" x2="105" y2="120" stroke="#cccccc" stroke-width="4" stroke-linecap="round"/>
      <circle cx="140" cy="130" r="25" fill="#FFC107"/>
      <circle cx="130" cy="120" r="4" fill="#000000"/>
      <circle cx="150" cy="120" r="4" fill="#000000"/>
      <circle cx="140" cy="140" r="4" fill="#000000"/>
      <line x1="132" y1="122" x2="138" y2="138" stroke="#000000" stroke-width="2"/>
      <line x1="148" y1="122" x2="142" y2="138" stroke="#000000" stroke-width="2"/>
    </svg>''',
    // Slide 3
    '''<svg viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
      <circle cx="100" cy="100" r="60" stroke="#555555" stroke-width="12" fill="none"/>
      <circle cx="100" cy="100" r="20" fill="#555555"/>
      <path d="M 100 120 L 100 160 M 85 95 L 45 80 M 115 95 L 155 80" stroke="#555555" stroke-width="10"/>
      <rect x="130" y="30" width="40" height="70" rx="8" fill="#111111" stroke="#FFC107" stroke-width="3"/>
      <circle cx="150" cy="65" r="10" fill="#FFC107" opacity="0.5"/>
      <circle cx="150" cy="65" r="20" stroke="#FFC107" stroke-width="2" fill="none" stroke-dasharray="4"/>
      <circle cx="150" cy="65" r="30" stroke="#FFC107" stroke-width="1" fill="none" opacity="0.5"/>
      <path d="M 140 10 L 145 20 L 150 10 L 155 20 L 160 10 L 160 25 L 140 25 Z" fill="#FFC107"/>
    </svg>''',
    // Slide 4
    '''<svg viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
      <line x1="20" y1="50" x2="180" y2="50" stroke="#333333" stroke-width="1" stroke-dasharray="4"/>
      <line x1="20" y1="100" x2="180" y2="100" stroke="#333333" stroke-width="1" stroke-dasharray="4"/>
      <line x1="20" y1="150" x2="180" y2="150" stroke="#333333" stroke-width="1" stroke-dasharray="4"/>
      <rect x="40" y="90" width="20" height="60" rx="4" fill="#666666"/>
      <rect x="70" y="60" width="20" height="90" rx="4" fill="#FFC107"/>
      <rect x="100" y="110" width="20" height="40" rx="4" fill="#444444"/>
      <path d="M 150 50 C 135 50 135 75 150 90 C 165 75 165 50 150 50 Z" fill="#FFC107"/>
      <circle cx="150" cy="62" r="6" fill="#111111"/>
      <rect x="30" y="20" width="140" height="25" rx="5" fill="#222222" stroke="#444444" stroke-width="2"/>
      <circle cx="45" cy="32.5" r="5" fill="#FFC107"/>
      <line x1="60" y1="32.5" x2="120" y2="32.5" stroke="#cccccc" stroke-width="3" stroke-linecap="round"/>
    </svg>''',
    // Slide 5
    '''<svg viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
      <path d="M 120 100 A 20 20 0 1 1 80 100 A 20 20 0 1 1 120 100" fill="none" stroke="#FFC107" stroke-width="12" stroke-dasharray="15 5"/>
      <circle cx="100" cy="100" r="15" fill="#FFC107"/>
      <rect x="50" y="150" width="100" height="6" rx="3" fill="#444444"/>
      <circle cx="120" cy="153" r="10" fill="#FFC107"/>
      <text x="40" y="158" fill="#888888" font-size="14" font-weight="bold">A</text>
      <text x="160" y="158" fill="#ffffff" font-size="20" font-weight="bold">A</text>
      <rect x="70" y="40" width="60" height="30" rx="15" fill="#FFC107"/>
      <circle cx="110" cy="55" r="12" fill="#000000"/>
    </svg>'''
  ];

  Widget _buildGraphic(int index) {
    if (index >= 0 && index < _svgGraphics.length) {
      return SvgPicture.string(
        _svgGraphics[index],
        width: 180,
        height: 180,
      );
    }
    return const SizedBox();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final dialogMaxHeight = screenHeight * 0.85;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxHeight: dialogMaxHeight),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white10),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 5),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _finishOnboarding,
                child: Text(
                  '건너뛰기',
                  style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.5)),
                ),
              ),
            ),
            Flexible(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentIndex = index),
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 그래픽 영역 (세련된 위젯으로 변경)
                        Container(
                          height: 180,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: _buildGraphic(index),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // 타이틀 텍스트 (두께를 얇게, 색상은 목업처럼 노란빛 추가)
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber, // 목업 디자인 반영
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 본문 텍스트 (얇고 깔끔하게)
                        Text(
                          page.description,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                        if (page.warningText != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              page.warningText!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.redAccent,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ]
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 8,
                        width: _currentIndex == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: _currentIndex == index 
                              ? Colors.amber 
                              : Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _nextPage,
                      child: Text(
                        _currentIndex == _pages.length - 1 ? '동의하고 시작하기' : '다음으로',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPageData {
  final String title;
  final String description;
  final String? warningText;

  _OnboardingPageData({
    required this.title,
    required this.description,
    this.warningText,
  });
}
