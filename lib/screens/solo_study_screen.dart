import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:sleek_circular_slider/sleek_circular_slider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:kiosk_mode/kiosk_mode.dart';

import '../services/study_session_service.dart';

class SoloStudyScreen extends StatefulWidget {
  const SoloStudyScreen({super.key});

  @override
  State<SoloStudyScreen> createState() => _SoloStudyScreenState();
}

class _SoloStudyScreenState extends State<SoloStudyScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isRecording = false;
  bool _isStudying = false;
  bool _isFaceDetected = false;
  bool _isLookingAtScreen = false;
  bool _isProcessing = false;
  bool _persistSession = true;

  bool _isLockMode = false;
  DateTime? _lockUntil;
  Duration _lockRemaining = Duration.zero;

  Duration _studyDuration = Duration.zero;
  Timer? _studyTimer;
  Timer? _captureTimer;
  Timer? _saveTimer;
  Timer? _lockTimer;

  int _requiredAdsToUnlock = 0;
  int _watchedAds = 0;
  RewardedAd? _rewardedAd;
  bool _isAdLoading = false;
  bool _isExitWarningDialogOpen = false;
  StateSetter? _exitWarningDialogSetState;

  final StudySessionService _sessionService = StudySessionService.instance;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedSession();
    _initializeCamera();
    _loadRewardedAd();
    WakelockPlus.enable();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_persistSession) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveSession();
    } else if (state == AppLifecycleState.resumed) {
      _loadSavedSession();
    }
  }

  Future<void> _loadSavedSession() async {
    final savedDuration = await _sessionService.getStudyDuration();
    final wasActive = await _sessionService.isSessionActive();
    if (!mounted) return;
    setState(() => _studyDuration = savedDuration);
    if (wasActive && _isCameraInitialized) {
      _startStudySession();
    }
  }

  Future<void> _saveSession() async {
    if (!_persistSession) return;
    await _sessionService.saveStudyDuration(_studyDuration);
    await _sessionService.setSessionActive(_isRecording);
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final front = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() => _isCameraInitialized = true);
      final wasActive = await _sessionService.isSessionActive();
      if (wasActive) _startStudySession();
    } catch (e) {
      debugPrint('Camera init failed: $e');
    }
  }

  void _startStudySession() {
    if (_isRecording) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    setState(() {
      _isRecording = true;
    });

    _captureTimer?.cancel();
    _saveTimer?.cancel();
    _captureTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _captureAndProcess();
    });
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveSession();
    });
    _sessionService.setSessionActive(true);
  }

  void _stopStudySessionInternal() {
    _captureTimer?.cancel();
    _saveTimer?.cancel();
    _studyTimer?.cancel();
    _lockTimer?.cancel();

    setState(() {
      _isRecording = false;
      _isStudying = false;
      _isFaceDetected = false;
      _isLookingAtScreen = false;
      _isLockMode = false;
      _lockRemaining = Duration.zero;
      _lockUntil = null;
      _requiredAdsToUnlock = 0;
      _watchedAds = 0;
    });

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _saveSession();
    _sessionService.setSessionActive(false);
  }

  void _stopStudySession() {
    if (_isLockMode && _lockRemaining > Duration.zero) {
      _showLockedMessage();
      return;
    }

    _stopStudySessionInternal();
  }

  void _resetSession() {
    if (_isLockMode && _lockRemaining > Duration.zero) {
      _showLockedMessage();
      return;
    }
    _stopStudySession();
    setState(() {
      _studyDuration = Duration.zero;
    });
    _sessionService.resetSession();
  }

  Future<void> _captureAndProcess() async {
    if (!_isRecording) return;
    if (_isProcessing || _cameraController == null) return;
    if (!_cameraController!.value.isInitialized) return;

    _isProcessing = true;
    try {
      final imageFile = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final faces = await _faceDetector.processImage(inputImage);
      try {
        await File(imageFile.path).delete();
      } catch (_) {}
      if (mounted) _updateStudyState(faces);
    } catch (e) {
      debugPrint('Face process failed: $e');
    } finally {
      _isProcessing = false;
    }
  }

  void _updateStudyState(List<Face> faces) {
    if (!_isRecording) {
      _studyTimer?.cancel();
      return;
    }

    final wasFaceDetected = _isFaceDetected;
    final wasLookingAtScreen = _isLookingAtScreen;

    if (faces.isEmpty) {
      _isFaceDetected = false;
      _isLookingAtScreen = false;
    } else {
      _isFaceDetected = true;
      final face = faces.first;
      final leftEyeOpen = face.leftEyeOpenProbability ?? 0.5;
      final rightEyeOpen = face.rightEyeOpenProbability ?? 0.5;
      final headYAngle = face.headEulerAngleY ?? 0;
      final headXAngle = face.headEulerAngleX ?? 0;

      final isLookingFront = headYAngle.abs() < 25 && headXAngle.abs() < 25;
      final eyesOpen = leftEyeOpen > 0.2 && rightEyeOpen > 0.2;
      _isLookingAtScreen = isLookingFront && eyesOpen;
    }

    final shouldStudy = _isRecording && _isFaceDetected && !_isLookingAtScreen;
    if (shouldStudy != _isStudying) {
      setState(() {
        _isStudying = shouldStudy;
      });
      if (shouldStudy) {
        _startTimer();
      } else {
        _studyTimer?.cancel();
      }
    }

    if (wasFaceDetected != _isFaceDetected || wasLookingAtScreen != _isLookingAtScreen) {
      setState(() {});
    }
  }

  void _startTimer() {
    _studyTimer?.cancel();
    _studyTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isStudying) {
        setState(() {
          _studyDuration += const Duration(seconds: 1);
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  String _formatLock(Duration duration) {
    final mm = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hh = duration.inHours;
    if (hh > 0) return '$hh:$mm:$ss';
    return '$mm:$ss';
  }

  void _clearLockState() {
    _lockTimer?.cancel();
    _isLockMode = false;
    _lockUntil = null;
    _lockRemaining = Duration.zero;
    _requiredAdsToUnlock = 0;
    _watchedAds = 0;
  }

  Future<void> _releaseLockMode({bool stopSession = false}) async {
    _dismissExitWarningDialogIfOpen();
    if (mounted) {
      setState(_clearLockState);
    } else {
      _clearLockState();
    }
    try {
      await stopKioskMode();
    } catch (e) {
      debugPrint('Failed to stop kiosk mode: $e');
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (stopSession) {
      _stopStudySessionInternal();
    }
  }

  void _showResetDialog() {
    if (_isLockMode && _lockRemaining > Duration.zero) {
      _showLockedMessage();
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('공부 시간 초기화'),
        content: const Text('현재까지의 공부 시간을 초기화하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetSession();
            },
            child: const Text('초기화', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showLockedMessage() {
    _showExitWarningDialog();
  }

  void _loadRewardedAd() {
    if (_isAdLoading) return;
    _isAdLoading = true;
    RewardedAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/5224354917', // Test Ad Unit ID
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isAdLoading = false;
        },
        onAdFailedToLoad: (error) {
          _rewardedAd = null;
          _isAdLoading = false;
        },
      ),
    );
  }

  void _showRewardedAd() {
    if (_rewardedAd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('광고를 불러오는 중입니다. 잠시 후 다시 시도해주세요.')),
      );
      _loadRewardedAd();
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        _loadRewardedAd();
        if (mounted) _checkUnlockCondition();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd = null;
        _loadRewardedAd();
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        setState(() {
          _watchedAds++;
        });
        _exitWarningDialogSetState?.call(() {});
      },
    );
  }

  void _checkUnlockCondition() {
    if (_watchedAds >= _requiredAdsToUnlock) {
      unawaited(_releaseLockMode(stopSession: true).then((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('잠금 모드가 해제되었습니다.')),
        );
      }));
    } else {
      if (_isExitWarningDialogOpen) {
        _exitWarningDialogSetState?.call(() {});
      } else {
        _showLockedMessage();
      }
    }
  }

  void _dismissExitWarningDialogIfOpen() {
    if (!_isExitWarningDialogOpen || !mounted) return;
    _isExitWarningDialogOpen = false;
    _exitWarningDialogSetState = null;
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  Future<void> _startLockModeFlow() async {
    if (_isRecording) {
      if (_isLockMode && _lockRemaining > Duration.zero) {
        _showLockedMessage();
      } else {
        _stopStudySession();
      }
      return;
    }

    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) => const _LockDurationDialog(),
    );

    if (result == null) {
      if (!mounted) return;
      setState(_clearLockState);
      return;
    }
    
    final selectedMinutes = result['minutes'] ?? 25;
    final selectedAds = result['ads'] ?? 1;

    final lockDuration = Duration(minutes: selectedMinutes);
    final lockUntil = DateTime.now().add(lockDuration);

    setState(() {
      _isLockMode = true;
      _lockUntil = lockUntil;
      _lockRemaining = lockDuration;
      _requiredAdsToUnlock = selectedAds; 
      _watchedAds = 0;
    });

    startKioskMode();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _startStudySession();
    _lockTimer?.cancel();
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _lockUntil == null) return;
      final remaining = _lockUntil!.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        unawaited(_releaseLockMode().then((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('잠금 모드가 해제되었습니다.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }));
      } else {
        setState(() {
          _lockRemaining = remaining;
        });
        _exitWarningDialogSetState?.call(() {});
      }
    });
  }

  void _showExitWarningDialog() {
    if (_isLockMode && _lockRemaining > Duration.zero) {
      if (_watchedAds >= _requiredAdsToUnlock) {
        _checkUnlockCondition();
        return;
      }
      _isExitWarningDialogOpen = true;
      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, dialogSetState) {
            _exitWarningDialogSetState = dialogSetState;
            return AlertDialog(
              title: const Text('조기 종료 안내'),
              content: Text(
                '잠금 시간이 ${_formatLock(_lockRemaining)} 남았습니다.\n\n'
                '위급 상황 시 조기 종료하려면 광고를 시청해야 합니다.\n'
                '(시청 완료: $_watchedAds / $_requiredAdsToUnlock)',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC91428),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    _showRewardedAd();
                  },
                  child: const Text('광고 보고 잠금 해제하기'),
                ),
              ],
            );
          },
        ),
      ).then((_) {
        _isExitWarningDialogOpen = false;
        _exitWarningDialogSetState = null;
      });
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('앱 종료'),
        content: const Text('기록이 삭제되고 앱이 종료됩니다. 계속할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              _persistSession = false;
              _captureTimer?.cancel();
              _saveTimer?.cancel();
              _studyTimer?.cancel();
              _lockTimer?.cancel();
              _isRecording = false;
              _isStudying = false;
              _isFaceDetected = false;
              _isLookingAtScreen = false;
              _isLockMode = false;
              _lockUntil = null;
              _lockRemaining = Duration.zero;
              _studyDuration = Duration.zero;
              await _sessionService.resetSession();
              if (!mounted) return;
              await SystemNavigator.pop();
            },
            child: const Text('종료', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _rewardedAd?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (_persistSession) _saveSession();
    _captureTimer?.cancel();
    _saveTimer?.cancel();
    _studyTimer?.cancel();
    _lockTimer?.cancel();
    _cameraController?.dispose();
    _faceDetector.close();
    WakelockPlus.disable();
    super.dispose();
  }

  Color _getStatusColor() {
    if (!_isRecording) return Colors.grey;
    if (!_isFaceDetected) return Colors.orange;
    if (_isLookingAtScreen) return Colors.red;
    return Colors.green;
  }

  IconData _getStatusIcon() {
    if (!_isRecording) return Icons.pause_circle_outline;
    if (!_isFaceDetected) return Icons.person_off;
    if (_isLookingAtScreen) return Icons.visibility;
    return Icons.menu_book;
  }

  String _getStatusText() {
    if (!_isRecording) return '대기 중';
    if (!_isFaceDetected) return '얼굴 미감지';
    if (_isLookingAtScreen) return '딴짓 중';
    return '공부 중';
  }

  String _getHelpText() {
    if (!_isFaceDetected) return '카메라에 얼굴이 보이도록 해주세요.';
    if (_isLookingAtScreen) return '화면을 보면 타이머가 멈춥니다.';
    return '집중 중입니다.';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isLockMode) {
          _showLockedMessage();
        } else {
          _showExitWarningDialog();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_isCameraInitialized && _cameraController != null)
            Center(
              child: AspectRatio(
                aspectRatio: 1 / _cameraController!.value.aspectRatio,
                child: CameraPreview(_cameraController!),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.of(context).padding.top + 8,
                16,
                16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: _showExitWarningDialog,
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black26,
                          shape: const CircleBorder(),
                        ),
                      ),
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: _getStatusColor().withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_getStatusIcon(), color: Colors.white, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  _getStatusText(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_isLockMode &&
                              _isRecording &&
                              _lockUntil != null &&
                              _lockRemaining > Duration.zero)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  'LOCK ${_formatLock(_lockRemaining)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      IconButton(
                        onPressed: _showResetDialog,
                        icon: const Icon(Icons.refresh, color: Colors.white, size: 28),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black26,
                          shape: const CircleBorder(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Text(
                    _formatDuration(_studyDuration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 68,
                      fontWeight: FontWeight.w300,
                      fontFeatures: [FontFeature.tabularFigures()],
                      shadows: [
                        Shadow(
                          blurRadius: 10,
                          color: Colors.black45,
                          offset: Offset(2, 2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 240 + MediaQuery.of(context).padding.bottom,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                ),
              ),
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 96,
                    width: double.infinity,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Center(child: _buildRecordButton()),
                        Positioned(
                          right: MediaQuery.of(context).size.width * 0.15,
                          child: _buildLockRecordButton(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      _isRecording ? _getHelpText() : '버튼을 눌러 공부를 시작하세요',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        shadows: const [
                          Shadow(
                            blurRadius: 2,
                            color: Colors.black87,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }

  Widget _buildRecordButton() {
    return GestureDetector(
      onTap: () {
        if (_isRecording) {
          _stopStudySession();
        } else {
          _startStudySession();
        }
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 5),
              borderRadius: BorderRadius.circular(_isRecording ? 24 : 40),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFFF2D2D),
              borderRadius: BorderRadius.circular(_isRecording ? 12 : 30),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockRecordButton() {
    return GestureDetector(
      onTap: _startLockModeFlow,
      child: SizedBox(
        width: 48,
        height: 48,
        child: const Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.lock, color: Colors.white, size: 30),
          ],
        ),
      ),
    );
  }
}

class _LockDurationDialog extends StatefulWidget {
  const _LockDurationDialog();

  @override
  State<_LockDurationDialog> createState() => _LockDurationDialogState();
}

class _LockDurationDialogState extends State<_LockDurationDialog> {
  int _minutes = 25;
  int _requiredAds = 1;

  String _formatDisplay(int totalMinutes) {
    if (totalMinutes < 60) {
      return '$totalMinutes분';
    }
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (minutes == 0) return '$hours시간';
    return '$hours시간 $minutes분';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('잠금 시간 설정', textAlign: TextAlign.center),
      backgroundColor: const Color(0xFF1D2D44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          SleekCircularSlider(
            appearance: CircularSliderAppearance(
              size: 220,
              customColors: CustomSliderColors(
                progressBarColors: [const Color(0xFF2D9CDB), const Color(0xFF1B6FB5)],
                trackColor: Colors.white.withValues(alpha: 0.1),
                dotColor: Colors.white,
                shadowColor: const Color(0xFF1B6FB5),
              ),
              customWidths: CustomSliderWidths(
                progressBarWidth: 14,
                trackWidth: 14,
                handlerSize: 12,
              ),
              infoProperties: InfoProperties(
                mainLabelStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                modifier: (double value) {
                  return _formatDisplay(value.round());
                },
              ),
            ),
            min: 1,
            max: 1440,
            initialValue: _minutes.toDouble(),
            onChange: (double value) {
              setState(() {
                _minutes = value.round();
              });
            },
          ),
          const SizedBox(height: 10),
          const Text('조기 종료 패널티', style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final adCount = index + 1;
              final isSelected = _requiredAds == adCount;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _requiredAds = adCount;
                  });
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFC91428) : Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? const Color(0xFFC91428) : Colors.white24,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$adCount개',
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white54,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소', style: TextStyle(color: Colors.grey)),
        ),
        const SizedBox(width: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFC91428),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: () => Navigator.pop(context, {'minutes': _minutes, 'ads': _requiredAds}),
          child: const Text('잠금 시작', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
