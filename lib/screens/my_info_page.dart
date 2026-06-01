import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/font_size_service.dart';

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
                  backgroundColor: const Color(0xFF1F222A),
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
              const SizedBox(height: 64),
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
            ],
          );
        },
      ),
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
        backgroundColor: const Color(0xFF1F222A),
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
      // 로그아웃 시 AuthService 상태가 unauthenticated로 바뀌고,
      // main.dart의 Consumer가 이를 감지하여 자동으로 LoginPage로 이동함.
    }
  }
}
