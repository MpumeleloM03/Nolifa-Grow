import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

class PlantIdService {
  static const String _apiKey = 'HcyulXOCMY8YUp4yKhwArRyOTbP3xvvL64btk77sGE2oHavYZG';
  static const String _baseUrl = 'https://plant.id/api/v3';

  Future<Map<String, dynamic>?> diagnose(File imageFile) async {
    try {
      print('PlantId: Starting diagnosis...');

      final imageBytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      print('PlantId: Image encoded, size: ${base64Image.length}');

      final response = await http.post(
        Uri.parse('$_baseUrl/health_assessment'),
        headers: {
          'Api-Key': _apiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'images': [base64Image],
          'health': 'all',
        }),
      );

      print('PlantId: Response status: ${response.statusCode}');
      print('PlantId: Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return _parseResponse(data);
      } else {
        print('PlantId: Error response: ${response.body}');
        return null;
      }
    } catch (e) {
      print('PlantId: Exception: $e');
      return null;
    }
  }

  Map<String, dynamic>? _parseResponse(Map<String, dynamic> data) {
    try {
      print('PlantId: Parsing response...');
      final result = data['result'];
      final isHealthy = result['is_healthy']['binary'];
      final healthProbability = result['is_healthy']['probability'];

      if (isHealthy) {
        return {
          'label': 'Healthy',
          'confidence': (healthProbability * 100).toStringAsFixed(1),
          'isHealthy': true,
          'diseases': [],
        };
      }

      final diseases = result['disease']['suggestions'] as List;
      if (diseases.isEmpty) {
        return {
          'label': 'Unknown',
          'confidence': '0',
          'isHealthy': false,
          'diseases': [],
        };
      }

      final topDisease = diseases[0];
      final diseaseName = topDisease['name'];
      final probability = topDisease['probability'];

      return {
        'label': diseaseName,
        'confidence': (probability * 100).toStringAsFixed(1),
        'isHealthy': false,
        'diseases': diseases
            .take(3)
            .map((d) => {
                  'name': d['name'],
                  'confidence':
                      (d['probability'] * 100).toStringAsFixed(1),
                })
            .toList(),
      };
    } catch (e) {
      print('PlantId: Parse error: $e');
      return null;
    }
  }
}