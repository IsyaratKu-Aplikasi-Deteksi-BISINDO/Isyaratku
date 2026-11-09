
import 'dart:convert';

import 'package:http/http.dart' as http;

// =====================================================
// HASIL PREDIKSI API
// =====================================================

class PredictionResult {
  final int classId;
  final String label;
  final double confidence;

  const PredictionResult({
    required this.classId,
    required this.label,
    required this.confidence,
  });

  factory PredictionResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return PredictionResult(
      classId: (json['class_id'] as num).toInt(),
      label: json['label'] as String,
      confidence: (json['confidence'] as num).toDouble(),
    );
  }
}

// =====================================================
// API SERVICE
// =====================================================

class ApiService {
  // Alamat IP komputer yang menjalankan FastAPI.
  static const String baseUrl = 'http://192.168.1.32:8000';

  static const String predictEndpoint = '/v1/predict';

  final http.Client _client;

  ApiService({http.Client? client})
      : _client = client ?? http.Client();

  // ===================================================
  // PREDIKSI BISINDO
  // ===================================================

  Future<PredictionResult> predict(
    List<List<double>> sequence,
  ) async {
    // Validasi jumlah frame.
    if (sequence.length != 30) {
      throw Exception(
        'Sequence harus terdiri dari 30 frame.',
      );
    }

    // Validasi jumlah fitur setiap frame.
    for (int i = 0; i < sequence.length; i++) {
      if (sequence[i].length != 66) {
        throw Exception(
          'Frame ${i + 1} harus memiliki 66 fitur.',
        );
      }

      if (sequence[i].any((value) => !value.isFinite)) {
        throw Exception(
          'Ditemukan nilai koordinat tidak valid.',
        );
      }
    }

    final uri = Uri.parse(
      '$baseUrl$predictEndpoint',
    );

    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'sequence': sequence,
            }),
          )
          .timeout(
            const Duration(seconds: 15),
          );

      final responseData = jsonDecode(response.body);

      if (response.statusCode != 200) {
        throw Exception(
          'API Error ${response.statusCode}: '
          '${responseData['detail'] ?? response.body}',
        );
      }

      if (responseData['success'] != true) {
        throw Exception(
          'Prediksi gagal diproses oleh server.',
        );
      }

      final prediction = responseData['prediction'];

      if (prediction is! Map<String, dynamic>) {
        throw Exception(
          'Format hasil prediksi tidak valid.',
        );
      }

      return PredictionResult.fromJson(prediction);
    } catch (e) {
      if (e is http.ClientException) {
        throw Exception(
          'Tidak dapat terhubung ke server FastAPI.',
        );
      }

      rethrow;
    }
  }

  // ===================================================
  // DISPOSE
  // ===================================================

  void dispose() {
    _client.close();
  }
}
