import 'package:speech_to_text/speech_to_text.dart';
import 'dart:async';

class VoiceService {
  final _speech = SpeechToText();
  bool _isInitialized = false;

  Future<bool> init() async {
    if (!_isInitialized) {
      _isInitialized = await _speech.initialize();
    }
    return _isInitialized;
  }

  Future<String?> listen() async {
    if (!_isInitialized) {
      await init();
    }
    
    if (!_speech.isAvailable) {
      return null;
    }

    final completer = Completer<String?>();
    String spoken = '';
    
    if (!await _speech.listen(
      onResult: (result) {
        spoken = result.recognizedWords;
        if (result.finalResult) {
          completer.complete(spoken);
        }
      },
      listenFor: Duration(seconds: 10),
      pauseFor: Duration(seconds: 3),
      cancelOnError: true,
      partialResults: true,
    )) {
      completer.complete(null);
    }
    
    // Set a timeout in case we don't get a final result
    Timer(Duration(seconds: 15), () {
      if (!completer.isCompleted) {
        _speech.stop();
        completer.complete(spoken.isNotEmpty ? spoken : null);
      }
    });
    
    return completer.future;
  }
}
