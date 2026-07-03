import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../services/subscription_service.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class PaywallPage extends StatefulWidget {
  const PaywallPage({super.key});

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  bool _isLoading = false;
  Offerings? _offerings;

  @override
  void initState() {
    super.initState();
    _fetchOfferings();
  }

  Future<void> _fetchOfferings() async {
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
    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('구독이 완료되었습니다. 프리미엄 기능을 이용해 보세요!')),
        );
        Navigator.pop(context);
      } else {
        // 취소하거나 에러가 발생한 경우 (조용히 넘어가도 무방)
      }
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isLoading = true);
    final success = await SubscriptionService.restorePurchases();
    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('구매 내역이 복원되었습니다.')),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('복원할 구매 내역이 없습니다.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 패키지를 쉽게 찾기 위한 헬퍼
    Package? monthlyPkg;
    Package? yearlyPkg;

    if (_offerings != null && _offerings!.current != null) {
      monthlyPkg = _offerings!.current!.monthly;
      yearlyPkg = _offerings!.current!.annual;
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1E2128), // 다크 톤 배경
              Color(0xFF0F1115),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              // 헤더 영역
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '운행일지관리 프리미엄\n무제한으로 누려보세요',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // 기능 목록
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildFeatureItem(
                      icon: FontAwesomeIcons.bolt,
                      title: '콜카드 무제한 퀵 등록',
                      subtitle: '광고 시청 없이 다중 콜카드를 한 번에 자동 입력하세요.',
                    ),
                    _buildFeatureItem(
                      icon: FontAwesomeIcons.robot,
                      title: 'OCR 자동 파싱 프리패스',
                      subtitle: '이미지 속 운행 정보를 텍스트로 완벽하게 변환해 줍니다.',
                    ),
                    _buildFeatureItem(
                      icon: FontAwesomeIcons.chartPie,
                      title: '상세 운행 통계',
                      subtitle: '기간별, 플랫폼별 상세한 순익 분석 리포트를 제공합니다.',
                    ),
                    _buildFeatureItem(
                      icon: FontAwesomeIcons.bell,
                      title: '스마트 알림창 퀵기능',
                      subtitle: '화면 상단 알림창에서 오늘 실적을 실시간으로 확인하세요.',
                    ),
                  ],
                ),
              ),

              // 구독 상품 영역 (Glassmorphism 카드)
              Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Column(
                  children: [
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.all(32.0),
                        child: CircularProgressIndicator(color: Color(0xFFFFC700)),
                      )
                    else ...[
                      // 연간 구독 (추천)
                      _buildPackageCard(
                        title: '연간 구독 (추천)',
                        priceString: yearlyPkg != null ? yearlyPkg.storeProduct.priceString : '₩25,000',
                        subtitle: '연 25,000원 (약 17% 할인)',
                        isHighlight: true,
                        onTap: () {
                          if (yearlyPkg != null) {
                            _purchasePackage(yearlyPkg);
                          } else {
                            // 설정 전 테스트용 모의 UI
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('구글 스토어 연동 전 미리보기 화면입니다.')),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // 월간 구독
                      _buildPackageCard(
                        title: '월간 구독',
                        priceString: monthlyPkg != null ? monthlyPkg.storeProduct.priceString : '₩2,500',
                        subtitle: '매월 자동 결제',
                        isHighlight: false,
                        onTap: () {
                          if (monthlyPkg != null) {
                            _purchasePackage(monthlyPkg);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('구글 스토어 연동 전 미리보기 화면입니다.')),
                            );
                          }
                        },
                      ),
                    ]
                  ],
                ),
              ),

              // 하단 액션 (복원 및 약관)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _isLoading ? null : _restorePurchases,
                      child: const Text(
                        '구매 복원',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                    const Text('|', style: TextStyle(color: Colors.white24, fontSize: 12)),
                    TextButton(
                      onPressed: () {},
                      child: const Text(
                        '이용 약관',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem({
    required dynamic icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFFC700).withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: icon is IconData 
                ? Icon(icon, color: const Color(0xFFFFC700), size: 20)
                : FaIcon(icon, color: const Color(0xFFFFC700), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white60,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageCard({
    required String title,
    required String priceString,
    required String subtitle,
    required bool isHighlight,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isHighlight ? const Color(0xFFFFC700).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isHighlight ? const Color(0xFFFFC700) : Colors.white.withOpacity(0.1),
            width: isHighlight ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isHighlight ? const Color(0xFFFFC700) : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isHighlight ? const Color(0xFFFFC700).withOpacity(0.8) : Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              priceString,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
