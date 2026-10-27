import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:dbros_app/services/subscription_service.dart';
import 'package:dbros_app/services/premium_service.dart';
import 'package:url_launcher/url_launcher.dart';

class PaywallPage extends StatefulWidget {
  const PaywallPage({Key? key}) : super(key: key);

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  bool _isLoading = false;
  Offerings? _offerings;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    setState(() => _isLoading = true);
    final offerings = await SubscriptionService.getOfferings();
    if (mounted) {
      setState(() {
        _offerings = offerings;
        _isLoading = false;
      });
    }
  }

  Future<void> _purchasePackage(Package package) async {
    setState(() => _isLoading = true);
    final success = await SubscriptionService.purchasePackage(package);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('프리미엄 구독이 시작되었습니다. 감사합니다!')),
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('결제가 취소되었거나 실패했습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '운행일지관리\n프리미엄 구독',
                  style: TextStyle(
                    color: Color(0xFFFFC700),
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  '커피 한 잔 값으로 매일 반복되는 광고와\n수기입력 스트레스를 끝내세요!',
                  style: TextStyle(color: Color(0xFFD1D2D4), fontSize: 15, height: 1.45),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                if (PremiumService.canStartLaunchTrial) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: const Color(0x1F00E676),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF00E676),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E676),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '🎁 출시기념 1회 한정 혜택',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const Text(
                              '자동결제 없음',
                              style: TextStyle(
                                color: Color(0xFF00E676),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '아직 14일 무료 체험을 안 쓰셨네요!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '카드 등록이나 결제 없이 14일 동안 모든 프리미엄 기능을 먼저 무료로 경험해 보세요.',
                          style: TextStyle(
                            color: Color(0xFFD1D2D4),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E676),
                            foregroundColor: Colors.black,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () async {
                            final started =
                                await PremiumService.tryStartLaunchTrialWithFeedback(
                                  context,
                                );
                            if (started && context.mounted) {
                              Navigator.of(context).pop(true);
                            }
                          },
                          child: const Text(
                            '🎁 결제 없이 14일 무료 체험 먼저 시작하기',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else
                  const SizedBox(height: 8),

                // Benefits
                _buildBenefitItem(Icons.document_scanner, '스크린샷 자동 일지 등록', '화면 캡처 한 번으로 복잡한 운행일지가 자동으로 작성됩니다.'),
                _buildBenefitItem(Icons.bar_chart, '상세 수익 통계 대시보드', '일/주/월/년 단위 수익과 지출 통계와 프로그램별 그래프로 파악하세요.'),
                _buildBenefitItem(Icons.map, '일자별 운행 동선 지도', '오늘 내가 이동한 전체 경로와 총 운행 거리를 지도로 꼼꼼히 확인하세요.'),
                _buildBenefitItem(Icons.block, '광고 완벽 제거', '앱 내의 모든 광고가 제거되어 더욱 쾌적하게 이용하실 수 있습니다.'),
                _buildBenefitItem(Icons.bolt, '팝업창 빠른 등록 (플로팅 버튼)', '다른 앱 위에 팝업을 띄워 화면 전환 없이 어디서든 빠르게 일지를 등록하세요.'),
                
                const SizedBox(height: 32),

                // Subscription Options
                const Text(
                  '정기 구독',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                
                if (_offerings != null && _offerings!.current != null && _offerings!.current!.availablePackages.isNotEmpty)
                  ..._offerings!.current!.availablePackages.map((pkg) => _buildPackageCard(pkg)).toList()
                else
                  // Fallback UI if RevenueCat is not configured yet
                  Column(
                    children: [
                      _buildMockPackageCard('프리미엄 월간 구독', '3,000원', ' / 월', false),
                      _buildMockPackageCard('프리미엄 연간 구독', '27,000원', ' / 년', true, originalPrice: '36,000원'),
                    ],
                  ),

                const SizedBox(height: 32),

                // 구독 취소 안내
                Center(
                  child: Column(
                    children: [
                      const Text(
                        '구독은 언제든지 취소할 수 있습니다.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () async {
                          try {
                            await launchUrl(
                              Uri.parse('https://play.google.com/store/account/subscriptions'),
                              mode: LaunchMode.externalApplication,
                            );
                          } catch (_) {}
                        },
                        child: const Text(
                          'Google Play > 구독 관리에서 취소 가능',
                          style: TextStyle(
                            color: Color(0xFF6B9FFF),
                            fontSize: 12,
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFF6B9FFF),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700))),
            ),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFC700).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFFFFC700), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageCard(Package package) {
    final isAnnual = package.packageType == PackageType.annual;
    return GestureDetector(
      onTap: () => _purchasePackage(package),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isAnnual ? const Color(0xFFFFC700).withOpacity(0.15) : const Color(0xFF1E2024),
          border: Border.all(color: isAnnual ? const Color(0xFFFFC700) : Colors.transparent, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    package.storeProduct.title,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      isAnnual ? '25% 특가 할인! · 1년 내내 무제한' : '하루 이용료 100원 · 언제든 해지 가능',
                      style: TextStyle(
                        color: isAnnual ? const Color(0xFFFFC700) : const Color(0xFF9FA3AE),
                        fontSize: 12,
                        fontWeight: isAnnual ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isAnnual)
                  const Text('36,000원', style: TextStyle(color: Colors.grey, fontSize: 12, decoration: TextDecoration.lineThrough)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      package.storeProduct.priceString,
                      style: TextStyle(color: isAnnual ? const Color(0xFFFFC700) : Colors.white, fontSize: isAnnual ? 18 : 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      isAnnual ? ' / 년' : ' / 월',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMockPackageCard(String title, String currentPrice, String period, bool isAnnual, {String? originalPrice}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isAnnual ? const Color(0xFFFFC700).withOpacity(0.15) : const Color(0xFF1E2024),
        border: Border.all(color: isAnnual ? const Color(0xFFFFC700) : Colors.transparent, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    isAnnual ? '25% 특가 할인! · 1년 내내 무제한' : '하루 이용료 100원 · 언제든 해지 가능',
                    style: TextStyle(
                      color: isAnnual ? const Color(0xFFFFC700) : const Color(0xFF9FA3AE),
                      fontSize: 12,
                      fontWeight: isAnnual ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (originalPrice != null)
                Text(originalPrice, style: const TextStyle(color: Colors.grey, fontSize: 12, decoration: TextDecoration.lineThrough)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    currentPrice,
                    style: TextStyle(color: isAnnual ? const Color(0xFFFFC700) : Colors.white, fontSize: isAnnual ? 18 : 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    period,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
