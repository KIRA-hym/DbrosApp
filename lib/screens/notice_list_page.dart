import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/db_helper.dart';

class NoticeListPage extends StatefulWidget {
  const NoticeListPage({super.key});

  @override
  State<NoticeListPage> createState() => _NoticeListPageState();
}

class _NoticeListPageState extends State<NoticeListPage> {
  List<Map<String, dynamic>> _notices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotices();
  }

  Future<void> _loadNotices() async {
    try {
      final data = await DriveLogDatabase.instance.getNotices();
      if (mounted) {
        setState(() {
          _notices = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        title: const Text('공지사항', style: TextStyle(fontFamily: 'GmarketSans', fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1F222A),
        elevation: 0,
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)));
    }
    if (_notices.isEmpty) {
      return const Center(
        child: Text('수신된 공지사항이 없습니다.', style: TextStyle(color: Colors.white70)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _notices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final data = _notices[index];
        final id = data['id'] as int? ?? 0;
        final title = data['title'] as String? ?? '제목 없음';
        final body = data['body'] as String? ?? '내용 없음';
        final receivedAt = data['received_at'] as String?;
        final isRead = (data['is_read'] as int? ?? 0) == 1;

        String dateStr = '';
        if (receivedAt != null && receivedAt.isNotEmpty) {
          try {
            final dt = DateTime.parse(receivedAt).toLocal();
            dateStr = DateFormat('yyyy-MM-dd HH:mm').format(dt);
          } catch (_) {}
        }

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1F222A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2C2F36)),
          ),
          child: ExpansionTile(
            onExpansionChanged: (expanded) async {
              if (expanded && !isRead) {
                await DriveLogDatabase.instance.markNoticeAsRead(id);
                if (mounted) {
                  setState(() {
                    _notices[index]['is_read'] = 1;
                  });
                }
              }
            },
            shape: const RoundedRectangleBorder(side: BorderSide.none),
            collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
            iconColor: const Color(0xFFFFC700),
            collapsedIconColor: Colors.white70,
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$id.',
                  style: const TextStyle(color: Color(0xFFFFC700), fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: isRead ? Colors.white70 : Colors.white,
                            fontSize: 16,
                            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                            height: 1.3,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'N',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            subtitle: dateStr.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 8, left: 24),
                    child: Text(
                      dateStr,
                      style: const TextStyle(color: Color(0xFF6E717C), fontSize: 12),
                    ),
                  )
                : null,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFF2C2F36))),
                ),
                child: Text(
                  body,
                  style: const TextStyle(color: Color(0xFFD4D6DD), fontSize: 14, height: 1.6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
