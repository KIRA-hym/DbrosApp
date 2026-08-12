import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/db_helper.dart';
import '../widgets/app_glass_dialog.dart';
import '../providers/notice_badge_provider.dart';

class NoticeListPage extends StatefulWidget {
  const NoticeListPage({super.key});

  @override
  State<NoticeListPage> createState() => _NoticeListPageState();
}

class _NoticeListPageState extends State<NoticeListPage> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoadingNotifications = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<NoticeBadgeProvider>(context, listen: false).markAsRead();
    });
  }

  Future<void> _loadNotifications() async {
    try {
      final data = await DriveLogDatabase.instance.getNotices();
      if (mounted) {
        setState(() {
          _notifications = data;
          _isLoadingNotifications = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingNotifications = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF121418),
        appBar: AppBar(
          title: const Text('공지 및 알림', style: TextStyle(fontFamily: 'GmarketSans', fontWeight: FontWeight.bold)),
          backgroundColor: Theme.of(context).cardTheme.color!,
          elevation: 0,
          centerTitle: true,
          bottom: const TabBar(
            labelColor: Color(0xFFFFC700),
            unselectedLabelColor: Colors.white54,
            indicatorColor: Color(0xFFFFC700),
            tabs: [
              Tab(text: '공지목록'),
              Tab(text: '알림목록'),
            ],
          ),
          actions: [
            Builder(
              builder: (ctx) {
                return IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white70),
                  onPressed: () async {
                    // Only apply to 알림목록
                    final tabController = DefaultTabController.of(ctx);
                    if (tabController.index == 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('알림목록 탭에서만 전체 삭제가 가능합니다.')),
                      );
                      return;
                    }

                    if (_notifications.isEmpty) return;
                    final confirm = await AppGlassDialog.show<bool>(
                      context: context,
                      dialog: AppGlassDialog(
                        icon: Icons.delete_outline,
                        title: '알림목록 삭제',
                        content: '수신된 알림목록을 모두 삭제하시겠습니까?',
                        actions: [
                          Builder(builder: (c) => GlassDialogCancelButton(onPressed: () => Navigator.pop(c, false), label: '아니오')),
                          Builder(builder: (c) => GlassDialogDestructiveButton(label: '예', onPressed: () => Navigator.pop(c, true))),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await DriveLogDatabase.instance.deleteAllNotices();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('알림목록이 성공적으로 삭제되었습니다.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            backgroundColor: Color(0xFFFFC700),
                            duration: Duration(seconds: 2),
                          ),
                        );
                        await _loadNotifications();
                      }
                    }
                  },
                );
              }
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildGlobalNoticesTab(),
            _buildLocalNotificationsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalNoticesTab() {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('admin_push_requests')
          .orderBy('created_at', descending: true)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)));
        }
        if (snapshot.hasError) {
          return const Center(child: Text('공지를 불러오는 중 오류가 발생했습니다.', style: TextStyle(color: Colors.white70)));
        }
        
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('등록된 공지사항이 없습니다.', style: TextStyle(color: Colors.white70)));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final title = doc['title'] as String? ?? '제목 없음';
            final body = doc['body'] as String? ?? '내용 없음';
            final ts = doc['created_at'] as Timestamp?;
            String dateStr = '';
            if (ts != null) {
              dateStr = DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate());
            }

            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color!,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: ExpansionTile(
                shape: const RoundedRectangleBorder(side: BorderSide.none),
                collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
                iconColor: const Color(0xFFFFC700),
                collapsedIconColor: Colors.white70,
                title: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('📢 ', style: TextStyle(fontSize: 16)),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
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
      },
    );
  }

  Widget _buildLocalNotificationsTab() {
    if (_isLoadingNotifications) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)));
    }
    if (_notifications.isEmpty) {
      return const Center(
        child: Text('수신된 알림목록이 없습니다.', style: TextStyle(color: Colors.white70)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _notifications.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final data = _notifications[index];
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
            color: Theme.of(context).cardTheme.color!,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: ExpansionTile(
            onExpansionChanged: (expanded) async {
              if (expanded && !isRead) {
                await DriveLogDatabase.instance.markNoticeAsRead(id);
                if (mounted) {
                  setState(() {
                    _notifications[index]['is_read'] = 1;
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
                const Text(
                  '■',
                  style: TextStyle(color: Color(0xFFFFC700), fontSize: 14),
                ),
                const SizedBox(width: 10),
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
