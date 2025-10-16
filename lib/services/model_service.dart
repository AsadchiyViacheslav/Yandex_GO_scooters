import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'dart:math' as math;

class ScooterPrediction {
  final int scooterPresence;
  final double confidence;
  final int inferenceTime;
  final ParkingStatus? parkingStatus;

  ScooterPrediction({
    required this.scooterPresence,
    required this.confidence,
    required this.inferenceTime,
    this.parkingStatus,
  });
}

class ParkingStatus {
  final int type;
  final double confidence;
  final int inferenceTime;

  ParkingStatus({
    required this.type,
    required this.confidence,
    required this.inferenceTime,
  });
}

class ModelService {
  OrtSession? _scooterSession;
  OrtSession? _parkingSession;

  static const int inputWidth = 224;
  static const int inputHeight = 224;

  Future<void> loadModel() async {
    try {
      OrtEnv.instance.init();

      final sessionOptions = OrtSessionOptions();

      final scooterModelBytes = await rootBundle.load('assets/models/mobilenetv3_large.onnx');
      final scooterModelData = scooterModelBytes.buffer.asUint8List();
      _scooterSession = OrtSession.fromBuffer(scooterModelData, sessionOptions);

      print('Scooter detection model loaded');

      final parkingModelBytes = await rootBundle.load('assets/models/efficientnetv2s.onnx');
      final parkingModelData = parkingModelBytes.buffer.asUint8List();
      _parkingSession = OrtSession.fromBuffer(parkingModelData, sessionOptions);
      print('Parking detection model loaded');
    } catch (e) {
      print('Error loading models: $e');
      rethrow;
    }
  }

  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce(math.max);
    final exps = logits.map((x) => math.exp(x - maxLogit)).toList();
    final sumExp = exps.reduce((a, b) => a + b);
    return exps.map((x) => x / sumExp).toList();
  }

  Future<ScooterPrediction> predictScooterInImage(File imageFile) async {
    if (_scooterSession == null) {
      throw Exception('Scooter model not loaded');
    }

    try {
      final imageBytes = await imageFile.readAsBytes();
      final image = img.decodeImage(imageBytes);

      if (image == null) {
        throw Exception('Failed to decode image');
      }

      final resizedImage = img.copyResize(
        image,
        width: inputWidth,
        height: inputHeight,
        interpolation: img.Interpolation.linear,
      );

      // Конвертация в тензор [1, 3, 224, 224] с нормализацией
      final inputTensor = _imageToFloatTensor(resizedImage);

      final scooterStart = DateTime.now();
      
      final inputOrt = OrtValueTensor.createTensorWithDataList(
        inputTensor,
        [1, 3, inputHeight, inputWidth],
      );

      final inputs = {'input': inputOrt};
      final outputs = await _scooterSession!.runAsync(
        OrtRunOptions(),
        inputs,
      );

      final scooterEnd = DateTime.now();
      final scooterInferenceTime =
          scooterEnd.difference(scooterStart).inMilliseconds;

      final outputTensor = outputs![0]!.value as List<List<double>>;
      final predictions = outputTensor[0];
      final softmaxPredictions = _softmax(predictions);

      int predictedClass = 0;
      double maxConfidence = softmaxPredictions[0];

      for (int i = 1; i < softmaxPredictions.length; i++) {
        if (softmaxPredictions[i] > maxConfidence) {
          maxConfidence = softmaxPredictions[i];
          predictedClass = i;
        }
      }

      // Логирование результата
      print('\n═══ Scooter Detection Result ═══');
      print('Predicted class: $predictedClass');
      print('Class probabilities:');
      print(' PRED: ${outputTensor[0]}');
      print('  [0] No scooter: ${(softmaxPredictions[0] * 100).toStringAsFixed(2)}%');
      print('  [1] Partial: ${(softmaxPredictions[1] * 100).toStringAsFixed(2)}%');
      print('  [2] Full: ${(softmaxPredictions[2] * 100).toStringAsFixed(2)}%');
      print('Inference time: ${scooterInferenceTime}ms');
      print('════════════════════════════════\n');

      inputOrt.release();

      ParkingStatus? parkingStatus;
      int totalInferenceTime = scooterInferenceTime;
      if (predictedClass >= 1) {
        parkingStatus = await _predictParking(resizedImage);
        totalInferenceTime += parkingStatus.inferenceTime;
      } else {
        parkingStatus = ParkingStatus(type: 0, confidence: 0.0, inferenceTime: 0);
      }
      
      String finalResult;
      if (predictedClass == 0) {
        finalResult = 'no_scooter';
      } else if (parkingStatus!.type == 1) {
        finalResult = 'inside';
      } else if (parkingStatus!.type == 2) {
        finalResult = 'outside';
      } else {
        finalResult = 'hard_to_say';
      }

      print('FINAL RESULT: $finalResult');
      print('Total inference time: ${totalInferenceTime}ms');

      return ScooterPrediction(
        scooterPresence: predictedClass,
        confidence: maxConfidence,
        inferenceTime: totalInferenceTime,
        parkingStatus: parkingStatus, 
      );
    } catch (e) {
      print('Error during prediction: $e');
      rethrow;
    }
  }

  Future<ParkingStatus> _predictParking(img.Image resizedImage) async {
    if (_parkingSession == null) {
      throw Exception('Parking model not loaded');
    }

    try {
      final inputTensor = _imageToFloatTensor(resizedImage);

      final inferenceStart = DateTime.now();
      final inputOrt = OrtValueTensor.createTensorWithDataList(
        inputTensor,
        [1, 3, inputHeight, inputWidth],
      );

      final inputs = {'input': inputOrt};
      final outputs = await _parkingSession!.runAsync(OrtRunOptions(), inputs);
      final inferenceEnd = DateTime.now();
      final inferenceTime = inferenceEnd.difference(inferenceStart).inMilliseconds;

      final outputTensor = outputs![0]!.value as List<List<double>>;
      final predictions = outputTensor[0];
      final softmaxPredictions = _softmax(predictions);

      int predictedClass = 0;
      double maxConfidence = softmaxPredictions[0];
      for (int i = 1; i < softmaxPredictions.length; i++) {
        if (softmaxPredictions[i] > maxConfidence) {
          maxConfidence = softmaxPredictions[i];
          predictedClass = i;
        }
      }

      print('\n═══ Parking Detection Result ═══');
      print('Predicted class: $predictedClass');
      print('Class probabilities: ${softmaxPredictions.map((p) => (p*100).toStringAsFixed(2) + "%").toList()}');
      print('Inference time (parking): ${inferenceTime}ms');
      print('═════════════════════════════════\n');

      inputOrt.release();

      return ParkingStatus(
        type: predictedClass,
        confidence: maxConfidence,
        inferenceTime: inferenceTime,
      );
    } catch (e) {
      print('Error during parking prediction: $e');
      rethrow;
    }
  }

  Float32List _imageToFloatTensor(img.Image image) {
    final tensor = Float32List(3 * ModelService.inputHeight * ModelService.inputWidth);

    const mean = [0.485, 0.456, 0.406];
    const std = [0.229, 0.224, 0.225];

    int i = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = (pixel.r / 255.0 - mean[0]) / std[0];
        tensor[i++] = r;
      }
    }

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final g = (pixel.g / 255.0 - mean[1]) / std[1];
        tensor[i++] = g;
      }
    }

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final b = (pixel.b / 255.0 - mean[2]) / std[2];
        tensor[i++] = b;
      }
    }

    return tensor;
  }

  double exp(double x) {
    return _taylorSeriesExp(x);
  }

  double _taylorSeriesExp(double x) {
    double result = 1.0;
    double term = 1.0;
    for (int i = 1; i < 20; i++) {
      term *= x / i;
      result += term;
    }
    return result;
  }

  void dispose() {
    _scooterSession?.release();
    _parkingSession?.release();
  }
}