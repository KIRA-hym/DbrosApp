import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/font_size_service.dart';

class AdminUserListPage extends StatefulWidget {
  const AdminUserListPage({super.key});

  @override
  State<AdminUserListPage> createState() => _AdminUserListPageState();
}

class _AdminUserListPageState extends State<AdminUserListPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('유저 관리 (관리자)'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('users').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)));
          }
          if (snapshot.hasError) {
            return Center(child: Text('데이터를 불러오지 못했습니다.\n${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('가입한 유저가 없습니다.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            separatorBuilder: (context, index) => const Divider(color: Colors.white10),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              
              final String uid = doc.id;
              final String email = data['email'] ?? '이메일 없음';
              final String name = data['displayName'] ?? '이름 없음';
              final bool isBanned = data['isBanned'] == true;
              final bool isAdmin = data['isAdmin'] == true;
              
              String createdAtStr = '';
              if (data['createdAt'] != null) {
                try {
                  final ts = data['createdAt'];
                  if (ts is Timestamp) {
                    createdAtStr = DateFormat('yyyy.MM.dd HH:mm').format(ts.toDate());
                  }
                } catch (_) {}
              }

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isBanned ? Colors.redAccent.withOpacity(0.2) : Theme.of(context).cardTheme.color!,
                  child: Icon(
                    isAdmin ? Icons.admin_panel_settings : Icons.person,
                    color: isBanned ? Colors.redAccent : const Color(0xFFFFC700),
                  ),
                ),
                title: Text(
                  name,
                  style: TextStyle(
                    fontSize: FontSizeService.getScaledFontSize(16),
                    fontWeight: FontWeight.w700,
                    color: isBanned ? Colors.grey : Colors.white,
                    decoration: isBanned ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      email,
                      style: TextStyle(
                        fontSize: FontSizeService.getScaledFontSize(12),
                        color: Colors.white70,
                      ),
                    ),
                    if (createdAtStr.isNotEmpty)
                      Text(
                        '가입: $createdAtStr',
                        style: TextStyle(
                          fontSize: FontSizeService.getScaledFontSize(10),
                          color: Colors.white54,
                        ),
                      ),
                  ],
                ),
                trailing: isAdmin
                    ? const Text('관리자', style: TextStyle(color: Color(0xFFFFC700), fontWeight: FontWeight.w700))
                    : Switch(
                        value: isBanned,
                        activeColor: Colors.redAccent,
                        inactiveThumbColor: const Color(0xFFFFC700),
                        inactiveTrackColor: Theme.of(context).cardTheme.color!,
                        onChanged: (val) => _toggleBanStatus(uid, val),
                      ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _toggleBanStatus(String uid, bool ban) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'isBanned': ban,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ban ? '해당 유저를 차단했습니다.' : '차단을 해제했습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('상태 변경 실패: $e')),
        );
      }
    }
  }
}
