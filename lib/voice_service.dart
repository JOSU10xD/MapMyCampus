import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';

/// Service to handle Text-to-Speech functionality for navigation.
class VoiceService {
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  bool _isSpeaking = false;
  bool _isMalayalam = false; // Default language is English

  /// Initializes the TTS engine.
  Future<void> init() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5); // Normal speed
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    // optimize for loud playback on iOS
    await _flutterTts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      [
        IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        IosTextToSpeechAudioCategoryOptions.duckOthers,
      ],
    );
    await _flutterTts.setSharedInstance(true);

    _flutterTts.setStartHandler(() {
      _isSpeaking = true;
    });

    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
    });

    _flutterTts.setErrorHandler((msg) {
      _isSpeaking = false;
      print("TTS Error: $msg");
    });
    
    // Audio Player listener
    _audioPlayer.onPlayerComplete.listen((event) {
      _isSpeaking = false;
    });
  }

  /// Sets the preferred language (false = English, true = Malayalam).
  void setLanguage(bool isMalayalam) {
    _isMalayalam = isMalayalam;
  }
  
  /// Gets current language status.
  bool get isMalayalam => _isMalayalam;

  /// Speaks the given text if not currently speaking (or interrupts if urgent).
  /// [interrupt] - If true, stops current speech to speak this new message.
  Future<void> speak(String text, {bool interrupt = false}) async {
    if (text.isEmpty) return;

    if (interrupt) {
      await stop();
    }

    if (!_isSpeaking || interrupt) {
      _isSpeaking = true;
      
      if (_isMalayalam) {
        // Malayalam Handling (Play MP3s)
        String lowerText = text.toLowerCase();
        
        try {
          if (lowerText.contains("turn right") || lowerText.contains("bear right")) {
            await _audioPlayer.play(AssetSource('right.mp3'));
          } else if (lowerText.contains("turn left") || lowerText.contains("bear left")) {
            await _audioPlayer.play(AssetSource('left.mp3'));
          } else if (lowerText.contains("have arrived")) {
            print("Playing Malayalam destination audio...");
            await _audioPlayer.play(AssetSource('reached_destination.mp3'));
          } else {
             // Fallback: Use English TTS for unmapped phrases?
            // Or just silent. User requested specific replacement.
            // Let's use English TTS as fallback so "Starting navigation" etc still works.
             await _flutterTts.setVolume(1.0);
             await _flutterTts.setSpeechRate(0.5);
             await _flutterTts.speak(text);
          }
        } catch (e) {
          print("Audio Player Error: $e");
          _isSpeaking = false;
        }
        
      } else {
        // English Handling (TTS)
        await _flutterTts.setVolume(1.0); // Ensure volume is max
        await _flutterTts.setSpeechRate(0.5); // Ensure normal speed
        await _flutterTts.speak(text);
      }
    }
  }

  /// Stops any active speech.
  Future<void> stop() async {
    await _flutterTts.stop();
    await _audioPlayer.stop();
    _isSpeaking = false;
  }
}
