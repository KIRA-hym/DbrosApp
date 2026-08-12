import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/db_helper.dart';
import 'package:sqflite/sqflite.dart';

class NoticeBadgeProvider extends ChangeNotifier {
  bool _hasUnread = false;
  bool get hasUnread => _hasUnread;

  static const String _lastReadNoticeTimeKey = 'last_read_notice_time';

  NoticeBadgeProvider() {
    checkUnreadNotices();
  }

  Future<void> checkUnreadNotices() async {
    try {
      // 1. Check local notifications (local_notices)
      final localUnreadCount = await _getUnreadLocalNoticeCount();
      if (localUnreadCount > 0) {
        _hasUnread = true;
        notifyListeners();
        return;
      }

      // 2. Check global notices (admin_push_requests)
      final hasUnreadGlobal = await _hasUnreadGlobalNotices();
      if (hasUnreadGlobal) {
        _hasUnread = true;
        notifyListeners();
        return;
      }

      _hasUnread = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error checking unread notices: $e');
    }
  }

  Future<int> _getUnreadLocalNoticeCount() async {
    try {
      final db = await DriveLogDatabase.instance.database;
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM local_notices WHERE is_read = 0');
      if (result.isNotEmpty) {
        return Sqflite.firstIntValue(result) ?? 0;
      }
    } catch (e) {
      debugPrint('Error querying local unread notices: $e');
    }
    return 0;
  }

  Future<bool> _hasUnreadGlobalNotices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastReadTime = prefs.getInt(_lastReadNoticeTimeKey) ?? 0;

      final snapshot = await FirebaseFirestore.instance
          .collection('admin_push_requests')
          .orderBy('created_at', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final ts = doc['created_at'] as Timestamp?;
        if (ts != null) {
          final latestNoticeTime = ts.millisecondsSinceEpoch;
          if (latestNoticeTime > lastReadTime) {
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking global notices: $e');
    }
    return false;
  }

  Future<void> markAsRead() async {
    try {
      // 1. Update global notice read time
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastReadNoticeTimeKey, DateTime.now().millisecondsSinceEpoch);

      // 2. Clear UI state immediately for responsive feel
      if (_hasUnread) {
        _hasUnread = false;
        notifyListeners();
      }
      
      // 3. Re-verify after a small delay to ensure local DB updates have settled
      Future.delayed(const Duration(milliseconds: 500), () {
        checkUnreadNotices();
      });

    } catch (e) {
      debugPrint('Error marking notices as read: $e');
    }
  }
}
