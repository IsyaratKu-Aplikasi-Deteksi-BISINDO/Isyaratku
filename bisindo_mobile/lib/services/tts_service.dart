
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();

  Future<void> initialize() async {
    await _flutterTts.setLanguage('id-ID');
    await _flutterTts.setSpeechRate(0.45);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.awaitSpeakCompletion(true);
  }

  Future<void> speak(String text) async {
    final String cleanedText = text.trim();

    if (cleanedText.isEmpty) return;

    await _flutterTts.stop();
    await _flutterTts.speak(cleanedText);
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }
}
