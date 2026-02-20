import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/study_session_service.dart';

class SoloStudyScreen extends StatefulWidget {
  const SoloStudyScreen({super.key});

  @override
  State<SoloStudyScreen> createState() => _SoloStudyScreenState();
}

class _SoloStudyScreenState extends State<SoloStudyScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  CameraDescription? _frontCamera;
  bool _isCameraInitialized = false;
  bool _isRecording = false;
  bool _isStudying = false;
  bool _isFaceDetected = false;
  bool _isLookingAtScreen = false;

  Duration _studyDuration = Duration.zero;
  Timer? _timer;
  Timer? _captureTimer;
  Timer? _saveTimer;

  final StudySessionService _sessionService = StudySessionService.instance;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedSession();
    _initializeCamera();
    WakelockPlus.enable();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveSession();
    }
    if (state == AppLifecycleState.resumed) {
      _loadSavedSession();
    }
  }

  Future<void> _loadSavedSession() async {
    final savedDuration = await _sessionService.getStudyDuration();
    final wasActive = await _sessionService.isSessionActive();

    if (!mounted) return;

    setState(() {
      _studyDuration = savedDuration;
    });

    if (wasActive && _isCameraInitialized) {
      _startStudySession();
    }
  }

  Future<void> _saveSession() async {
    await _sessionService.saveStudyDuration(_studyDuration);
    await _sessionService.setSessionActive(_isRecording);
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) return;

      _frontCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        _frontCamera!,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
      });

      final wasActive = await _sessionService.isSessionActive();
      if (wasActive) {
        _startStudySession();
      }
    } catch (e) {
      debugPrint('카메라 초기화 실패: $e');
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

    _captureTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      _captureAndProcess();
    });

    _saveTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _saveSession();
    });

    _sessionService.setSessionActive(true);
  }

  void _stopStudySession() {
    _captureTimer?.cancel();
    _saveTimer?.cancel();
    _timer?.cancel();

    setState(() {
      _isRecording = false;
      _isStudying = false;
      _isFaceDetected = false;
      _isLookingAtScreen = false;
    });

    _saveSession();
    _sessionService.setSessionActive(false);
  }

  void _resetSession() {
    _stopStudySession();
    setState(() {
      _studyDuration = Duration.zero;
    });
    _sessionService.resetSession();
  }

  Future<void> _captureAndProcess() async {
    if (_isProcessing || _cameraController == null) return;
    if (!_cameraController!.value.isInitialized) return;

    _isProcessing = true;
    try {
      final XFile imageFile = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final faces = await _faceDetector.processImage(inputImage);

      try {
        await File(imageFile.path).delete();
      } catch (_) {}

      if (mounted) {
        _updateStudyState(faces);
      }
    } catch (e) {
      debugPrint('얼굴 인식 처리 실패: $e');
    } finally {
      _isProcessing = false;
    }
  }

  void _updateStudyState(List<Face> faces) {
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

    final shouldStudy = _isFaceDetected && !_isLookingAtScreen;
    if (shouldStudy != _isStudying) {
      setState(() {
        _isStudying = shouldStudy;
      });

      if (shouldStudy) {
        _startTimer();
      } else {
        _pauseTimer();
      }
    }

    if (wasFaceDetected != _isFaceDetected || wasLookingAtScreen != _isLookingAtScreen) {
      setState(() {});
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _isStudying) {
        setState(() {
          _studyDuration += const Duration(seconds: 1);
        });
      }
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveSession();
    _captureTimer?.cancel();
    _saveTimer?.cancel();
    _timer?.cancel();
    _cameraController?.dispose();
    _faceDetector.close();
    WakelockPlus.disable();
    super.dispose();
  }

  void _showResetDialog() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
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
                  colors: [
                    Colors.black.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () {
                          _saveSession();
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black26,
                          shape: const CircleBorder(),
                        ),
                      ),
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
            height: 220 + MediaQuery.of(context).padding.bottom,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom,
              ),
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Positioned(
                    top: 30,
                    child: GestureDetector(
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
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 5,
                              ),
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: _isRecording ? 40 : 66,
                            height: _isRecording ? 40 : 66,
                            decoration: BoxDecoration(
                              color: _isRecording ? Colors.red : Colors.white,
                              borderRadius: BorderRadius.circular(_isRecording ? 6 : 33),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 130,
                    left: 20,
                    right: 20,
                    child: Text(
                      _isRecording ? _getHelpText() : '공부를 시작하려면 버튼을 누르세요',
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
    );
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
    if (!_isFaceDetected) {
      return '카메라에 얼굴이 보이도록 해주세요';
    }
    if (_isLookingAtScreen) {
      return '휴대폰 화면을 보면 타이머가 멈춰요.\n책을 보면 다시 시작해요.';
    }
    return '집중이 잘 되고 있어요. 계속 이어가세요.';
  }
}
