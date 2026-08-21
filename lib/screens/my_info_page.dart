import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'paywall_page.dart';
import '../services/auth_service.dart';
import '../services/font_size_service.dart';
import 'cs_inquiry_page.dart';

class MyInfoPage extends StatelessWidget {
  const MyInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 정보'),
      ),
      body: Consumer<AuthService>(
        builder: (context, auth, child) {
          final user = auth.user;
          final userDoc = auth.userDoc;

          if (user == null) {
            return const Center(child: Text('로그인 정보가 없습니다.'));
          }

          final photoUrl = user.photoURL;
          final displayName = user.displayName ?? '이름 없음';
          final email = user.email ?? '이메일 없음';
          
          String createdAtStr = '-';
          if (userDoc != null && userDoc['createdAt'] != null) {
            final ts = userDoc['createdAt'];
            if (ts is num) {
              // 밀리초나 초 단위 timestamp 처리 방어코드 (보통 Timestamp 타입)
            } else {
              try {
                final date = ts.toDate();
                createdAtStr = DateFormat('yyyy.MM.dd HH:mm').format(date);
              } catch (_) {}
            }
          }

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: Theme.of(context).cardTheme.color!,
                  backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                      ? NetworkImage(photoUrl)
                      : null,
                  child: (photoUrl == null || photoUrl.isEmpty)
                      ? const Icon(Icons.person, size: 48, color: Color(0xFF6E717C))
                      : null,
                ),
              ),
              const SizedBox(height: 24),
              _buildInfoRow('이름', displayName),
              const Divider(color: Colors.white10, height: 32),
              _buildInfoRow('이메일', email),
              const Divider(color: Colors.white10, height: 32),
              _buildInfoRow('가입일자', createdAtStr),
              const Divider(color: Colors.white10, height: 32),
              // _buildPromotionCodeRow(context, userDoc), // 심사 반려 방지 위해 임시 숨김 처리 (결제 모듈 개발 후 해제 예정)
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CsInquiryPage()),
                  );
                },
                icon: const Icon(Icons.headset_mic, color: Colors.white),
                label: Text(
                  '고객지원 (이메일 문의)',
                  style: TextStyle(
                    fontSize: FontSizeService.getScaledFontSize(16),
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2C2F36), // 어두운 색상으로 차별화
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _handleLogout(context),
                icon: const Icon(Icons.logout, color: Colors.black87),
                label: Text(
                  '로그아웃',
                  style: TextStyle(
                    fontSize: FontSizeService.getScaledFontSize(16),
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC700),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _handleDeleteAccount(context),
                child: Text(
                  '회원 탈퇴',
                  style: TextStyle(
                    fontSize: FontSizeService.getScaledFontSize(14),
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF6E717C),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPromotionCodeRow(BuildContext context, Map<String, dynamic>? userDoc) {
    final premiumUntil = userDoc?['premiumUntil'];
    String premiumText = '미적용';
    bool isActive = false;
    if (premiumUntil != null) {
      final date = (premiumUntil as dynamic).toDate();
      if (date.isAfter(DateTime.now())) {
        isActive = true;
        premiumText = '${DateFormat('yyyy.MM.dd').format(date)} 까지';
      } else {
        premiumText = '만료됨';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '프리미엄 기능',
              style: TextStyle(
                color: const Color(0xFF9FA3AE),
                fontSize: FontSizeService.getScaledFontSize(14),
                fontWeight: FontWeight.w400,
              ),
            ),
            Text(
              premiumText,
              style: TextStyle(
                color: isActive ? const Color(0xFFFFC700) : Colors.white,
                fontSize: FontSizeService.getScaledFontSize(14),
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => _handlePromotionCode(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2C2F36),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            elevation: 0,
          ),
          child: Text(
            '프로모션 코드 입력',
            style: TextStyle(
              fontSize: FontSizeService.getScaledFontSize(13),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PaywallPage()),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFC700).withOpacity(0.15),
            foregroundColor: const Color(0xFFFFC700),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            elevation: 0,
          ),
          child: Text(
            isActive ? '프리미엄 구독 관리' : '운행일지관리 프리미엄 시작',
            style: TextStyle(
              fontSize: FontSizeService.getScaledFontSize(13),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  void _handlePromotionCode(BuildContext context) {
    final controller = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).cardTheme.color!,
              title: const Text('프로모션 코드 입력', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('발급받으신 프로모션 코드를 입력해주세요.', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    style: const TextStyle(color: Colors.white),
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: '코드를 입력하세요 (예: DBROS2026XXXXXX)',
                      hintStyle: const TextStyle(color: Colors.white30),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.white24),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFFFFC700)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.black26,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(ctx),
                  child: const Text('취소', style: TextStyle(color: Color(0xFF9FA3AE))),
                ),
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final code = controller.text.trim();
                          if (code.isEmpty) return;

                          setState(() => isLoading = true);
                          try {
                            await AuthService.instance.applyPromotionCode(code);
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('프로모션 코드가 성공적으로 적용되었습니다!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            setState(() => isLoading = false);
                            String errorMsg = e.toString().replaceAll('Exception:', '').trim();
                            if (!ctx.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(errorMsg),
                                backgroundColor: const Color(0xFFFF5252),
                              ),
                            );
                          }
                        },
                  child: isLoading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFC700)))
                      : const Text('적용하기', style: TextStyle(color: Color(0xFFFFC700))),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFF9FA3AE),
            fontSize: FontSizeService.getScaledFontSize(14),
            fontWeight: FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: FontSizeService.getScaledFontSize(16),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  void _handleLogout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardTheme.color!,
        title: const Text('로그아웃', style: TextStyle(color: Colors.white)),
        content: const Text('정말 로그아웃 하시겠습니까?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Color(0xFF9FA3AE))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('로그아웃', style: TextStyle(color: Color(0xFFFFC700))),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AuthService.instance.signOut();
    }
  }

  void _handleDeleteAccount(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardTheme.color!,
        title: const Text('회원 탈퇴', style: TextStyle(color: Color(0xFFFF5252))),
        content: const Text(
          '정말 탈퇴하시겠습니까?\n\n탈퇴 시 모든 데이터가 삭제되며 복구할 수 없습니다.\n\n⚠️ 주의: 앱스토어/플레이스토어에서 정기 구독 중인 상품이 있다면, 스토어에서 직접 구독을 해지하셔야 추가 결제가 발생하지 않습니다.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Color(0xFF9FA3AE))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('탈퇴하기', style: TextStyle(color: Color(0xFFFF5252))),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await AuthService.instance.deleteAccount();
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('탈퇴 처리에 실패했습니다. 재로그인 후 다시 시도해주세요.\n($e)'),
            backgroundColor: const Color(0xFFFF5252),
          ),
        );
      }
    }
  }
}
