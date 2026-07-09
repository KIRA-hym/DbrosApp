import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/db_helper.dart';
import '../utils/work_date_utils.dart';
import '../services/today_stats_notification_service.dart';

class WorkTimerProvider extends ChangeNotifier {
  bool _isClockedIn = false;
  DateTime? _clockInTime;
  int _elapsedSeconds = 0;
  Timer? _timer;

  bool get isClockedIn => _isClockedIn;
  int get elapsedSeconds => _elapsedSeconds;

  static const String _prefClockInKey = 'work_timer_clock_in_time';
  static const String _prefElapsedKey = 'work_timer_elapsed_seconds';
  static const String _prefWorkDateKey = 'work_timer_work_date';

  String? _currentWorkDate;

  static WorkTimerProvider? instance;

  WorkTimerProvider() {
    instance = this;
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final clockInStr = prefs.getString(_prefClockInKey);
    final savedElapsed = prefs.getInt(_prefElapsedKey) ?? 0;
    final savedWorkDate = prefs.getString(_prefWorkDateKey);
    
    final currentWorkDate = WorkDateUtils.effectiveWorkDateYmd();

    if (clockInStr != null && savedWorkDate != null) {
      _clockInTime = DateTime.tryParse(clockInStr);
      
      if (savedWorkDate == currentWorkDate && _clockInTime != null) {
        _isClockedIn = true;
        _currentWorkDate = currentWorkDate;
        final diff = DateTime.now().difference(_clockInTime!).inSeconds;
        _elapsedSeconds = savedElapsed + diff;
        _startTimer();
      } else if (savedWorkDate != currentWorkDate && _clockInTime != null) {
        // 날짜가 지난 경우 -> 강제 퇴근 처리
        _isClockedIn = false;
        await _forceClockOutForRollover(savedWorkDate);
      } else {
        await _clearState(prefs);
      }
    } else {
      await _clearState(prefs);
      // 퇴근 상태이더라도 오늘 일자의 저장된 근무시간이 있다면 불러와서 표시
      final session = await DriveLogDatabase.instance.getDailyWorkSession(currentWorkDate);
      if (session != null) {
        _elapsedSeconds = (session['total_seconds'] as int?) ?? 0;
        _currentWorkDate = currentWorkDate;
      } else {
        _elapsedSeconds = 0;
      }
    }
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final nowWorkDate = WorkDateUtils.effectiveWorkDateYmd();
      
      // 익일 오전 9시가 지나서 근무일자가 변경된 경우 (강제 퇴근)
      if (_currentWorkDate != null && nowWorkDate != _currentWorkDate) {
        _timer?.cancel();
        final oldDate = _currentWorkDate!;
        _forceClockOutForRollover(oldDate);
        return;
      }
      
      _elapsedSeconds++;
      notifyListeners();
    });
  }

  Future<void> clockIn({bool reset = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final currentWorkDate = WorkDateUtils.effectiveWorkDateYmd();

    if (reset) {
      _elapsedSeconds = 0;
      await DriveLogDatabase.instance.deleteDailyWorkSession(currentWorkDate);
    } else {
      // Check if there's saved DB data for today to continue from
      final session = await DriveLogDatabase.instance.getDailyWorkSession(currentWorkDate);
      if (session != null) {
        _elapsedSeconds = (session['total_seconds'] as int?) ?? 0;
      } else {
        _elapsedSeconds = 0;
      }
    }

    _isClockedIn = true;
    _clockInTime = DateTime.now();
    _currentWorkDate = currentWorkDate;
    
    await prefs.setString(_prefClockInKey, _clockInTime!.toIso8601String());
    await prefs.setInt(_prefElapsedKey, _elapsedSeconds);
    await prefs.setString(_prefWorkDateKey, currentWorkDate);

    _startTimer();
    notifyListeners();
    TodayStatsNotificationService.instance.refreshFromDbIfEnabled();
  }

  Future<void> clockInWithStartTime(DateTime startTime) async {
    final prefs = await SharedPreferences.getInstance();
    final currentWorkDate = WorkDateUtils.effectiveWorkDateYmd(startTime);

    // Get previous sessions if any (usually 0)
    final session = await DriveLogDatabase.instance.getDailyWorkSession(currentWorkDate);
    final previousElapsed = (session != null) ? ((session['total_seconds'] as int?) ?? 0) : 0;

    _isClockedIn = true;
    _clockInTime = startTime;
    _currentWorkDate = currentWorkDate;
    
    // UI에 보여질 현재 경과 시간 = 이전 세션 시간 + (현재 시간 - 소급 출근 시간)
    int diff = DateTime.now().difference(startTime).inSeconds;
    if (diff < 0) diff = 0;
    _elapsedSeconds = previousElapsed + diff;

    await prefs.setString(_prefClockInKey, _clockInTime!.toIso8601String());
    await prefs.setInt(_prefElapsedKey, previousElapsed); // 중요: loadState 시 중복 합산 방지를 위해 시작 시점의 이전 누적시간 저장
    await prefs.setString(_prefWorkDateKey, currentWorkDate);

    _startTimer();
    notifyListeners();
    TodayStatsNotificationService.instance.refreshFromDbIfEnabled();
  }

  Future<void> autoClockInIfNeeded() async {
    if (_isClockedIn) return;
    final currentWorkDate = WorkDateUtils.effectiveWorkDateYmd();
    
    // 오늘의 퇴근 기록이 이미 있으면 소급 자동출근 하지 않음 (사용자 요구사항 반영)
    final session = await DriveLogDatabase.instance.getDailyWorkSession(currentWorkDate);
    if (session != null) return;

    final logs = await DriveLogDatabase.instance.getRecentLogs(limit: 1);
    if (logs.isNotEmpty) {
      final lastLogDate = logs.first['work_date']?.toString();
      if (lastLogDate == currentWorkDate) {
        await clockIn(reset: false);
      }
    }
  }

  Future<void> clockOut() async {
    if (!_isClockedIn || _clockInTime == null) return;
    
    _timer?.cancel();
    
    _isClockedIn = false;
    notifyListeners(); // UI 즉시 반영
    
    try {
      final workDateToSave = _currentWorkDate ?? WorkDateUtils.effectiveWorkDateYmd();
      final clockOutTime = DateTime.now();
      
      // Save to DB
      await DriveLogDatabase.instance.saveDailyWorkSession(
        workDate: workDateToSave,
        totalSeconds: _elapsedSeconds,
        clockInTime: _clockInTime!.toIso8601String(),
        clockOutTime: clockOutTime.toIso8601String(),
      );

      // Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await _clearState(prefs);
    } catch (e) {
      debugPrint("clockOut error: $e");
    } finally {
      _clockInTime = null;
      _currentWorkDate = null;
      notifyListeners();
      TodayStatsNotificationService.instance.refreshFromDbIfEnabled();
    }
  }

  Future<void> _clearState(SharedPreferences prefs) async {
    await prefs.remove(_prefClockInKey);
    await prefs.remove(_prefElapsedKey);
    await prefs.remove(_prefWorkDateKey);
  }

  Future<void> resetWorkTimeForToday() async {
    final currentWorkDate = WorkDateUtils.effectiveWorkDateYmd();
    await DriveLogDatabase.instance.deleteDailyWorkSession(currentWorkDate);
    _elapsedSeconds = 0;
    
    // 혹시 모를 잔존 상태 제거
    final prefs = await SharedPreferences.getInstance();
    await _clearState(prefs);
    _isClockedIn = false;
    _clockInTime = null;
    _currentWorkDate = null;
    
    notifyListeners();
    TodayStatsNotificationService.instance.refreshFromDbIfEnabled();
  }

  Future<void> _forceClockOutForRollover(String oldWorkDate) async {
    try {
      final latestHm = await DriveLogDatabase.instance.getLatestDriveTimeHmOnWorkDate(oldWorkDate);
      
      if (latestHm == null) {
        // 일지가 하나도 없는 경우 -> 기록 삭제 (근무 취소)
        await DriveLogDatabase.instance.deleteDailyWorkSession(oldWorkDate);
      } else {
        // 일지가 있는 경우 -> 마지막 일지 시간 + 30분
        final actualDateYmd = WorkDateUtils.resolveDriveDateForNightShift(oldWorkDate, latestHm);
        DateTime? lastLogDateTime = DateTime.tryParse('$actualDateYmd $latestHm:00');
        
        if (lastLogDateTime != null) {
          DateTime clockOutTime = lastLogDateTime.add(const Duration(minutes: 30));
          
          // 만약 마지막 일지+30분이 이미 다음날 9시를 넘었다면 상한선(9시)으로 맞춤
          final boundaryTime = DateTime.parse('${WorkDateUtils.effectiveWorkDateYmd()} 09:00:00');
          if (clockOutTime.isAfter(boundaryTime)) {
            clockOutTime = boundaryTime;
          }
          
          // 출근 시간이 없으면 임시로 1초 전으로 설정 (방어 로직)
          final clockIn = _clockInTime ?? clockOutTime.subtract(const Duration(seconds: 1));
          
          int finalSeconds = clockOutTime.difference(clockIn).inSeconds;
          if (finalSeconds < 0) finalSeconds = 0;
          
          await DriveLogDatabase.instance.saveDailyWorkSession(
            workDate: oldWorkDate,
            totalSeconds: finalSeconds,
            clockInTime: clockIn.toIso8601String(),
            clockOutTime: clockOutTime.toIso8601String(),
          );
        }
      }
    } catch (e) {
      debugPrint("Force clock out error: $e");
    } finally {
      // SharedPreferences 정리
      final prefs = await SharedPreferences.getInstance();
      await _clearState(prefs);
      
      _isClockedIn = false;
      _clockInTime = null;
      _currentWorkDate = null;
      _elapsedSeconds = 0;
      notifyListeners();
      TodayStatsNotificationService.instance.refreshFromDbIfEnabled();
    }
  }

  String get formattedTime {
    final hours = _elapsedSeconds ~/ 3600;
    final minutes = (_elapsedSeconds % 3600) ~/ 60;
    final seconds = _elapsedSeconds % 60;
    
    final hStr = hours.toString().padLeft(2, '0');
    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');
    
    return '$hStr:$mStr:$sStr';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

