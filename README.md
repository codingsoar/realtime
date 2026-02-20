# Realtime

공부 집중 시간을 기록하는 Flutter 앱입니다.

## 빠른 시작
1. Flutter SDK 확인
   - `flutter --version`
2. 의존성 설치
   - `flutter pub get`
3. 실행
   - `flutter run`

## 현재 우선 범위(MVP)
- 상세: `docs/MVP_SCOPE.md`
- 핵심: 솔로 공부 타이머 안정화(측정/저장/복구)

## Firebase 설정
- 상세: `docs/FIREBASE_SETUP.md`
- 참고: 현재 iOS Firebase 설정 파일은 누락 상태입니다.

## 품질 점검
- 정적 분석: `flutter analyze`
- 테스트: `flutter test`

## 프로젝트 구조
- 앱 진입점: `lib/main.dart`
- 홈 화면: `lib/screens/home_screen.dart`
- 솔로 공부: `lib/screens/solo_study_screen.dart`
- 설정: `lib/screens/settings/settings_screen.dart`
- 세션 저장 서비스: `lib/services/study_session_service.dart`
