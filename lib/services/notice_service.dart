import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class NoticeService {
  NoticeService._();
  static final NoticeService instance = NoticeService._();

  /// 현재 날짜(KST)가 startDate <= today <= endDate 범위에 속하는 활성화된 공지사항 목록을 가져옵니다.
  Future<List<Map<String, dynamic>>> fetchActiveNotices() async {
    try {
      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      
      final snapshot = await FirebaseFirestore.instance
          .collection('notices')
          .orderBy('createdAt', descending: true)
          .get();

      final activeNotices = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final startDate = data['startDate'] as String? ?? '';
        final endDate = data['endDate'] as String? ?? '';
        
        if (startDate.isNotEmpty && endDate.isNotEmpty) {
          if (todayStr.compareTo(startDate) >= 0 && todayStr.compareTo(endDate) <= 0) {
            activeNotices.add({
              'id': doc.id,
              ...data,
            });
          }
        }
      }
      return activeNotices;
    } catch (e) {
      print('Notice fetch error: $e');
      return [];
    }
  }
}
