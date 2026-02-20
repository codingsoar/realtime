# Firebase Setup

## 현재 상태
- Android: `android/app/google-services.json` 존재
- iOS: `ios/Runner/GoogleService-Info.plist` 없음
- `flutterfire` CLI 미설치 상태

## 권장 절차
1. Firebase CLI 로그인
   - `firebase login`
2. FlutterFire CLI 설치
   - `dart pub global activate flutterfire_cli`
3. 프로젝트 루트에서 구성 실행
   - `flutterfire configure`
4. 생성 파일 확인
   - `lib/firebase_options.dart`
5. iOS 설정 파일 반영 확인
   - `ios/Runner/GoogleService-Info.plist`

## 코드 기준
- 앱은 Firebase 초기화 실패 시에도 실행되며 스플래시 상단에 안내 배지가 표시된다.
- Firebase 기능(인증/Firestore)은 설정 완료 후 정상 동작한다.
