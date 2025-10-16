import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/model_service.dart';

class PhotoModeScreen extends StatefulWidget {
  const PhotoModeScreen({super.key});

  @override
  State<PhotoModeScreen> createState() => _PhotoModeScreenState();
}

class _PhotoModeScreenState extends State<PhotoModeScreen> {
  File? _image;
  bool _isProcessing = false;
  bool _isModelLoaded = false;
  final ImagePicker _picker = ImagePicker();
  final ModelService _modelService = ModelService();

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await _initializeModel();
    });
  }

  Future<void> _initializeModel() async {
    try {
      await _modelService.loadModel();
      if (mounted) {
        setState(() => _isModelLoaded = true);
      }
      print('Model loaded successfully');
    } catch (e) {
      print('Error loading model: $e');
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

  Future<void> _pickImage(ImageSource source) async {
    if (!_isModelLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Модель ещё загружается...'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _image = File(pickedFile.path);
        });
        await _processImage();
      }
    } catch (e) {
      print('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выбора изображения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _processImage() async {
    if (_image == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final result = await _modelService.predictScooterInImage(_image!);
      if (mounted) {
        _showUnifiedResultDialog(result);
      }
    } catch (e) {
      print('Error processing image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка обработки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _showUnifiedResultDialog(ScooterPrediction result) {
    String resultText;
    Color resultColor;
    IconData resultIcon;

    if (result.scooterPresence == 0) {
      resultText = 'Самокат не обнаружен';
      resultColor = Colors.red;
      resultIcon = Icons.close;
    } else if (result.parkingStatus?.type == 1) {
      resultText = 'Самокат на парковке';
      resultColor = Colors.green;
      resultIcon = Icons.check_circle;
    } else if (result.parkingStatus?.type == 2) {
      resultText = 'Самокат вне парковки';
      resultColor = Colors.red;
      resultIcon = Icons.error;
    } else {
      resultText = 'Сложно сказать, сделай фото заново';
      resultColor = Colors.grey;
      resultIcon = Icons.help_outline;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: resultColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(resultIcon, size: 48, color: resultColor),
              ),
              const SizedBox(height: 20),
              const Text(
                'Результат анализа',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Text(
                resultText,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: resultColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Уверенность (самокат): ${(result.confidence * 100).toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
              if (result.parkingStatus != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Уверенность (парковка): ${(result.parkingStatus!.confidence * 100).toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'Время инференса: ${result.inferenceTime}мс',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Закрыть'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Режим фото',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: !_isModelLoaded
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFFFFCC00)),
                  SizedBox(height: 12),
                  Text('Загрузка моделей...'),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: _image == null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.photo_library_outlined,
                                  size: 80, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text('Выберите или сделайте фото',
                                  style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500)),
                            ],
                          )
                        : Stack(
                            alignment: Alignment.center,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(_image!, fit: BoxFit.contain),
                              ),
                              if (_isProcessing)
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircularProgressIndicator(
                                            color: Color(0xFFFFCC00)),
                                        SizedBox(height: 16),
                                        Text(
                                          'Анализ изображения...',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
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
                          onPressed: _isProcessing
                              ? null
                              : () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Галерея'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black,
                            side:
                                const BorderSide(color: Color(0xFFFFCC00)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
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
    _modelService.dispose();
    super.dispose();
  }
}
