import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TTSService {
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  TTSService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool _isPlaying = false;
  String? _currentText;
  Function(int, int)? _onProgress;
  Function()? _onComplete;

  // TTS Settings
  double _speechRate = 0.5;
  double _volume = 1.0;
  double _pitch = 1.0;
  String? _currentLanguage;
  String? _currentVoice;

  bool get isPlaying => _isPlaying;
  double get speechRate => _speechRate;
  double get volume => _volume;
  double get pitch => _pitch;
  String? get currentLanguage => _currentLanguage;
  String? get currentVoice => _currentVoice;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Set up TTS callbacks
      _flutterTts.setStartHandler(() {
        _isPlaying = true;
      });

      _flutterTts.setPauseHandler(() {
        _isPlaying = false;
      });

      _flutterTts.setContinueHandler(() {
        _isPlaying = true;
      });

      _flutterTts.setCompletionHandler(() {
        _isPlaying = false;
        _onComplete?.call();
      });

      _flutterTts.setProgressHandler((String text, int start, int end, String word) {
        _onProgress?.call(start, end);
      });

      _flutterTts.setErrorHandler((msg) {
        _isPlaying = false;
        if (kDebugMode) {
          print('TTS Error: $msg');
        }
      });

      // Set default settings
      await _flutterTts.setVolume(_volume);
      await _flutterTts.setSpeechRate(_speechRate);
      await _flutterTts.setPitch(_pitch);

      // Get available languages and voices
      final languages = await _flutterTts.getLanguages;
      if (languages.isNotEmpty) {
        _currentLanguage = languages.contains('en-US') ? 'en-US' : languages.first;
        await _flutterTts.setLanguage(_currentLanguage!);
      }

      _isInitialized = true;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to initialize TTS: $e');
      }
    }
  }

  Future<List<String>> getAvailableLanguages() async {
    try {
      final languages = await _flutterTts.getLanguages;
      return List<String>.from(languages);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, String>>> getAvailableVoices() async {
    try {
      final voices = await _flutterTts.getVoices;
      return List<Map<String, String>>.from(voices.map((voice) => 
        Map<String, String>.from(voice as Map)
      ));
    } catch (e) {
      return [];
    }
  }

  Future<void> setLanguage(String language) async {
    await _flutterTts.setLanguage(language);
    _currentLanguage = language;
  }

  Future<void> setVoice(Map<String, String> voice) async {
    await _flutterTts.setVoice(voice);
    _currentVoice = voice['name'];
  }

  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate.clamp(0.0, 1.0);
    await _flutterTts.setSpeechRate(_speechRate);
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _flutterTts.setVolume(_volume);
  }

  Future<void> setPitch(double pitch) async {
    _pitch = pitch.clamp(0.5, 2.0);
    await _flutterTts.setPitch(_pitch);
  }

  Future<void> speak(String text, {
    Function(int, int)? onProgress,
    Function()? onComplete,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    _currentText = text;
    _onProgress = onProgress;
    _onComplete = onComplete;

    await stop(); // Stop any current speech
    
    // Split text into chunks for better performance
    final chunks = _splitTextIntoChunks(text);
    
    for (final chunk in chunks) {
      if (!_isPlaying) break;
      await _flutterTts.speak(chunk);
      await _flutterTts.awaitSpeakCompletion(true);
    }
  }

  Future<void> pause() async {
    await _flutterTts.pause();
  }

  Future<void> stop() async {
    await _flutterTts.stop();
    _isPlaying = false;
  }

  List<String> _splitTextIntoChunks(String text, {int maxLength = 4000}) {
    if (text.length <= maxLength) {
      return [text];
    }

    final chunks = <String>[];
    final sentences = text.split(RegExp(r'[.!?]+'));
    
    String currentChunk = '';
    for (final sentence in sentences) {
      if (currentChunk.length + sentence.length > maxLength) {
        if (currentChunk.isNotEmpty) {
          chunks.add(currentChunk.trim());
          currentChunk = '';
        }
      }
      currentChunk += sentence + '. ';
    }
    
    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk.trim());
    }
    
    return chunks;
  }

  void dispose() {
    stop();
    _flutterTts.stop();
  }
}

// TTS Settings model
class TTSSettings {
  final double speechRate;
  final double volume;
  final double pitch;
  final String? language;
  final String? voice;
  final bool autoPlay;
  final bool highlightText;

  TTSSettings({
    this.speechRate = 0.5,
    this.volume = 1.0,
    this.pitch = 1.0,
    this.language,
    this.voice,
    this.autoPlay = false,
    this.highlightText = true,
  });

  TTSSettings copyWith({
    double? speechRate,
    double? volume,
    double? pitch,
    String? language,
    String? voice,
    bool? autoPlay,
    bool? highlightText,
  }) {
    return TTSSettings(
      speechRate: speechRate ?? this.speechRate,
      volume: volume ?? this.volume,
      pitch: pitch ?? this.pitch,
      language: language ?? this.language,
      voice: voice ?? this.voice,
      autoPlay: autoPlay ?? this.autoPlay,
      highlightText: highlightText ?? this.highlightText,
    );
  }

  Map<String, dynamic> toJson() => {
    'speechRate': speechRate,
    'volume': volume,
    'pitch': pitch,
    'language': language,
    'voice': voice,
    'autoPlay': autoPlay,
    'highlightText': highlightText,
  };

  factory TTSSettings.fromJson(Map<String, dynamic> json) => TTSSettings(
    speechRate: json['speechRate'] ?? 0.5,
    volume: json['volume'] ?? 1.0,
    pitch: json['pitch'] ?? 1.0,
    language: json['language'],
    voice: json['voice'],
    autoPlay: json['autoPlay'] ?? false,
    highlightText: json['highlightText'] ?? true,
  );
}