import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
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

  ScooterPrediction? _currentPrediction;

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
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
      if (_cameras!.isEmpty) throw Exception('Нет доступных камер');

      _cameraController = CameraController(
        _cameras![0],
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      setState(() {
        _isInitialized = true;
      });

      _startDetection();
    } catch (e) {
      print('Ошибка инициализации камеры: $e');
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

  void _startDetection() {
    _detectionTimer?.cancel();
    _detectionTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!_isProcessing &&
          _cameraController != null &&
          _cameraController!.value.isInitialized) {
        await _analyzeCameraFrame();
      }
    });
  }

  Future<void> _analyzeCameraFrame() async {
    if (_cameraController == null || _isProcessing) return;
    _isProcessing = true;

    try {
      final XFile image = await _cameraController!.takePicture();
      final result =
          await _modelService.predictScooterInImage(File(image.path));
      await File(image.path).delete();

      if (mounted) {
        setState(() => _currentPrediction = result);
      }
    } catch (e) {
      print('Ошибка анализа кадра: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _stopCamera() async {
    _detectionTimer?.cancel();
    await _cameraController?.dispose();
    _cameraController = null;
    setState(() => _isInitialized = false);
  }

  Widget _buildStatusBadge() {
    if (_currentPrediction == null) {
      return _statusBadge('Ожидание...', Icons.hourglass_empty, Colors.grey, '—');
    }

    String statusText;
    IconData statusIcon;
    Color statusColor;

    if (_currentPrediction!.scooterPresence == 0) {
      statusText = 'Самокат не обнаружен';
      statusIcon = Icons.close;
      statusColor = Colors.red;
    } else if (_currentPrediction!.parkingStatus == null) {
      statusText = 'Сложно сказать';
      statusIcon = Icons.help_outline;
      statusColor = Colors.grey;
    } else {
      switch (_currentPrediction!.parkingStatus!.type) {
        case 1:
          statusText = 'Самокат на парковке';
          statusIcon = Icons.check_circle;
          statusColor = Colors.green;
          break;
        case 2:
          statusText = 'Самокат вне парковки';
          statusIcon = Icons.error;
          statusColor = Colors.blueAccent;
          break;
        default:
          statusText = 'Сложно сказать';
          statusIcon = Icons.help_outline;
          statusColor = Colors.grey;
      }
    }

    return _statusBadge(
      statusText,
      statusIcon,
      statusColor,
      '${(_currentPrediction!.confidence * 100).toStringAsFixed(1)}%',
    );
  }

  Widget _statusBadge(String text, IconData icon, Color color, String confidence) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
              Text(
                '$confidence • ${_currentPrediction?.inferenceTime ?? '—'} мс',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w400),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Нажми "Камера", чтобы начать',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Режим видео',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
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
                if (!_isInitialized)
                  _buildPlaceholder(),
                if (_isInitialized && _cameraController != null)
                  CameraPreview(_cameraController!),
                if (_isInitialized)
                  Positioned(
                    top: 20,
                    left: 0,
                    right: 0,
                    child: Center(child: _buildStatusBadge()),
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
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isInitialized ? null : _initializeCamera,
                icon: const Icon(Icons.videocam),
                label: const Text('Камера'),
              ),
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
