import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import '../services/model_service.dart';

class VideoModeScreen extends StatefulWidget {
  const VideoModeScreen({super.key});

  @override
  State<VideoModeScreen> createState() => _VideoModeScreenState();
}

class _VideoModeScreenState extends State<VideoModeScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isProcessing = false;
  Timer? _detectionTimer;
  final ModelService _modelService = ModelService();
  final ImagePicker _picker = ImagePicker();

  ScooterPrediction? _currentPrediction;
  bool _isCameraMode = true;
  File? _videoFile;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      await _modelService.loadModel();
      print('✓ Model loaded successfully');
    } catch (e) {
      print('✗ Error loading model: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки модели: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isEmpty) {
        throw Exception('No cameras available');
      }

      _cameraController = CameraController(
        _cameras![0],
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      setState(() {
        _isInitialized = true;
        _isCameraMode = true;
      });

      _startDetection();
    } catch (e) {
      print('Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка инициализации камеры: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? pickedFile = await _picker.pickVideo(
        source: ImageSource.gallery,
      );

      if (pickedFile != null) {
        await _stopCamera();
        setState(() {
          _videoFile = File(pickedFile.path);
          _isCameraMode = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Видео выбрано. Обработка видео в реальном времени пока не реализована.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('Error picking video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выбора видео: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startDetection() {
    _detectionTimer?.cancel();
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_cameraController != null &&
          _cameraController!.value.isInitialized &&
          !_isProcessing) {
        _detectScooter();
      }
    });
  }

  Future<void> _detectScooter() async {
    if (_isProcessing || _cameraController == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final XFile image = await _cameraController!.takePicture();
      final result = await _modelService.predictScooterInImage(File(image.path));

      if (mounted) {
        setState(() {
          _currentPrediction = result;
        });
      }

      // Удаляем временное изображение
      await File(image.path).delete();
    } catch (e) {
      print('Error detecting scooter: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _stopCamera() async {
    _detectionTimer?.cancel();
    await _cameraController?.dispose();
    _cameraController = null;
    setState(() {
      _isInitialized = false;
    });
  }

  Widget _buildStatusBadge() {
    if (_currentPrediction == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.9),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Ожидание...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    String statusText;
    IconData statusIcon;
    Color statusColor;

    switch (_currentPrediction!.scooterPresence) {
      case 0:
        statusText = 'Самокат не обнаружен';
        statusIcon = Icons.close;
        statusColor = Colors.red;
        break;
      case 1:
        statusText = 'Самокат частично виден';
        statusIcon = Icons.warning_amber_rounded;
        statusColor = Colors.orange;
        break;
      case 2:
        statusText = 'Самокат обнаружен';
        statusIcon = Icons.check_circle;
        statusColor = Colors.green;
        break;
      default:
        statusText = 'Неизвестно';
        statusIcon = Icons.help;
        statusColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                statusText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${(_currentPrediction!.confidence * 100).toStringAsFixed(1)}% • ${_currentPrediction!.inferenceTime}мс',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Режим видео',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isInitialized)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _stopCamera,
              tooltip: 'Остановить камеру',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (!_isInitialized && _videoFile == null)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.videocam_outlined,
                          size: 80,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Выберите режим работы',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_isInitialized && _cameraController != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(0),
                    child: CameraPreview(_cameraController!),
                  ),
                if (_videoFile != null && !_isCameraMode)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.video_library,
                          size: 80,
                          color: Color(0xFFFFCC00),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Видео выбрано',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Обработка видео в реальном времени\nбудет добавлена в следующей версии',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                if (_isInitialized && _currentPrediction != null)
                  Positioned(
                    top: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _buildStatusBadge(),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickVideo,
                    icon: const Icon(Icons.video_library),
                    label: const Text('Видео'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Color(0xFFFFCC00)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isInitialized ? null : _initializeCamera,
                    icon: const Icon(Icons.videocam),
                    label: const Text('Камера'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _cameraController?.dispose();
    _modelService.dispose();
    super.dispose();
  }
}