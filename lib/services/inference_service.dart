import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class InferenceService {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isLoaded = false;
  String _loadError = '';

  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/plant_model.tflite',
      );
      await _loadLabels();
      _isLoaded = true;
    } catch (e) {
      _isLoaded = false;
      _loadError = e.toString();
    }
  }

  Future<void> _loadLabels() async {
    final labelData = await rootBundle.loadString(
      'assets/labels/labels.txt',
    );
    _labels = labelData
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .map((line) {
          // Remove leading numbers like "0 Healthy" → "Healthy"
          final parts = line.trim().split(' ');
          if (parts.length > 1 && int.tryParse(parts[0]) != null) {
            return parts.sublist(1).join(' ');
          }
          return line.trim();
        })
        .toList();
  }

  Future<Map<String, dynamic>?> diagnose(File imageFile) async {
    if (!_isLoaded || _interpreter == null) {
      return {
        'label': 'Model not loaded: $_loadError',
        'confidence': '0',
        'index': 0,
      };
    }

    try {
      final imageBytes = await imageFile.readAsBytes();
      final originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) {
        return {
          'label': 'Could not decode image',
          'confidence': '0',
          'index': 0,
        };
      }

      final resizedImage = img.copyResize(
        originalImage,
        width: 224,
        height: 224,
      );

      // Build flat Uint8List input buffer [1, 224, 224, 3]
      final inputBuffer = Uint8List(1 * 224 * 224 * 3);
      int pixelIndex = 0;
      for (int y = 0; y < 224; y++) {
        for (int x = 0; x < 224; x++) {
          final pixel = resizedImage.getPixel(x, y);
          inputBuffer[pixelIndex++] = pixel.r.toInt().clamp(0, 255);
          inputBuffer[pixelIndex++] = pixel.g.toInt().clamp(0, 255);
          inputBuffer[pixelIndex++] = pixel.b.toInt().clamp(0, 255);
        }
      }

      // Reshape buffer
      final input = inputBuffer.reshape([1, 224, 224, 3]);

      // Get output shape
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      final outputSize = outputShape[1];

      // Output buffer as Uint8List for quantized model
      final outputBuffer = Uint8List(outputSize);
      final output = outputBuffer.reshape([1, outputSize]);

      _interpreter!.run(input, output);

      // Find highest score
      int maxScore = 0;
      int maxIndex = 0;
      for (int i = 0; i < outputSize; i++) {
        if (outputBuffer[i] > maxScore) {
          maxScore = outputBuffer[i];
          maxIndex = i;
        }
      }

      // Debug — print all scores to terminal
      print('Output scores: $outputBuffer');
      print('Max score: $maxScore at index $maxIndex');

      // Convert uint8 score to percentage
      final confidence = ((maxScore / 255.0) * 100).toStringAsFixed(1);
      final label = maxIndex < _labels.length
          ? _labels[maxIndex]
          : 'Unknown';

      return {
        'label': label,
        'confidence': confidence,
        'index': maxIndex,
      };
    } catch (e) {
      return {
        'label': 'Error: ${e.toString()}',
        'confidence': '0',
        'index': 0,
      };
    }
  }

  void dispose() {
    _interpreter?.close();
  }
}