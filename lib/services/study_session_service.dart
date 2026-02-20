import 'package:shared_preferences/shared_preferences.dart';

/// 공부 세션 데이터를 저장/복구하는 서비스
class StudySessionService {
  static const String _keyStudySeconds = 'study_seconds';
  static const String _keySessionActive = 'session_active';
  static const String _keyLastUpdateTime = 'last_update_time';

  static StudySessionService? _instance;
  static StudySessionService get instance {
    _instance ??= StudySessionService._();
    return _instance!;
  }

  StudySessionService._();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 누적 공부 시간(초)
  Future<int> getStudySeconds() async {
    await init();
    return _prefs?.getInt(_keyStudySeconds) ?? 0;
  }

  /// 공부 시간 저장
  Future<void> saveStudySeconds(int seconds) async {
    await init();
    await _prefs?.setInt(_keyStudySeconds, seconds);
    await _prefs?.setInt(_keyLastUpdateTime, DateTime.now().millisecondsSinceEpoch);
  }

  /// 세션 활성화 여부
  Future<bool> isSessionActive() async {
    await init();
    return _prefs?.getBool(_keySessionActive) ?? false;
  }

  /// 세션 활성 상태 저장
  Future<void> setSessionActive(bool active) async {
    await init();
    await _prefs?.setBool(_keySessionActive, active);
    if (active) {
      await _prefs?.setInt(_keyLastUpdateTime, DateTime.now().millisecondsSinceEpoch);
    }
  }

  /// 마지막 업데이트 시각
  Future<DateTime?> getLastUpdateTime() async {
    await init();
    final timestamp = _prefs?.getInt(_keyLastUpdateTime);
    if (timestamp != null) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    return null;
  }

  /// 세션 초기화
  Future<void> resetSession() async {
    await init();
    await _prefs?.setInt(_keyStudySeconds, 0);
    await _prefs?.setBool(_keySessionActive, false);
    await _prefs?.remove(_keyLastUpdateTime);
  }

  Future<Duration> getStudyDuration() async {
    final seconds = await getStudySeconds();
    return Duration(seconds: seconds);
  }

  Future<void> saveStudyDuration(Duration duration) async {
    await saveStudySeconds(duration.inSeconds);
  }
}
