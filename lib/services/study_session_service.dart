import 'package:shared_preferences/shared_preferences.dart';

/// Persists study session state and elapsed time.
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

  /// Returns accumulated study seconds.
  Future<int> getStudySeconds() async {
    await init();
    return _prefs?.getInt(_keyStudySeconds) ?? 0;
  }

  /// Saves accumulated study seconds.
  Future<void> saveStudySeconds(int seconds) async {
    await init();
    await _prefs?.setInt(_keyStudySeconds, seconds);
    await _prefs?.setInt(_keyLastUpdateTime, DateTime.now().millisecondsSinceEpoch);
  }

  /// Returns whether a study session is active.
  Future<bool> isSessionActive() async {
    await init();
    return _prefs?.getBool(_keySessionActive) ?? false;
  }

  /// Updates active session state.
  Future<void> setSessionActive(bool active) async {
    await init();
    await _prefs?.setBool(_keySessionActive, active);
    if (active) {
      await _prefs?.setInt(_keyLastUpdateTime, DateTime.now().millisecondsSinceEpoch);
    }
  }

  /// Returns last update timestamp if present.
  Future<DateTime?> getLastUpdateTime() async {
    await init();
    final timestamp = _prefs?.getInt(_keyLastUpdateTime);
    if (timestamp != null) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    return null;
  }

  /// Clears all persisted session data.
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
