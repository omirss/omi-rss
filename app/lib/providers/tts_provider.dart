import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../features/tts/tts_service.dart';

// TTS Service provider
final ttsServiceProvider = Provider((ref) => TTSService());

// TTS Settings provider
final ttsSettingsProvider = StateNotifierProvider<TTSSettingsNotifier, TTSSettings>((ref) {
  return TTSSettingsNotifier(ref);
});

class TTSSettingsNotifier extends StateNotifier<TTSSettings> {
  final Ref ref;
  static const String _prefsKey = 'tts_settings';

  TTSSettingsNotifier(this.ref) : super(TTSSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = prefs.getString(_prefsKey);
    if (settingsJson != null) {
      state = TTSSettings.fromJson(json.decode(settingsJson));
      _applySettings();
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, json.encode(state.toJson()));
  }

  Future<void> _applySettings() async {
    final tts = ref.read(ttsServiceProvider);
    await tts.setSpeechRate(state.speechRate);
    await tts.setVolume(state.volume);
    await tts.setPitch(state.pitch);
    if (state.language != null) {
      await tts.setLanguage(state.language!);
    }
  }

  Future<void> setSpeechRate(double rate) async {
    state = state.copyWith(speechRate: rate);
    await ref.read(ttsServiceProvider).setSpeechRate(rate);
    await _saveSettings();
  }

  Future<void> setVolume(double volume) async {
    state = state.copyWith(volume: volume);
    await ref.read(ttsServiceProvider).setVolume(volume);
    await _saveSettings();
  }

  Future<void> setPitch(double pitch) async {
    state = state.copyWith(pitch: pitch);
    await ref.read(ttsServiceProvider).setPitch(pitch);
    await _saveSettings();
  }

  Future<void> setLanguage(String language) async {
    state = state.copyWith(language: language);
    await ref.read(ttsServiceProvider).setLanguage(language);
    await _saveSettings();
  }

  Future<void> setVoice(String voice) async {
    state = state.copyWith(voice: voice);
    await _saveSettings();
  }

  void toggleAutoPlay() {
    state = state.copyWith(autoPlay: !state.autoPlay);
    _saveSettings();
  }

  void toggleHighlightText() {
    state = state.copyWith(highlightText: !state.highlightText);
    _saveSettings();
  }
}

// TTS playback state
final ttsPlaybackProvider = StateNotifierProvider<TTSPlaybackNotifier, TTSPlaybackState>((ref) {
  return TTSPlaybackNotifier(ref);
});

class TTSPlaybackState {
  final bool isPlaying;
  final bool isPaused;
  final String? currentText;
  final int currentPosition;
  final int totalLength;
  final double progress;

  TTSPlaybackState({
    this.isPlaying = false,
    this.isPaused = false,
    this.currentText,
    this.currentPosition = 0,
    this.totalLength = 0,
    this.progress = 0.0,
  });

  TTSPlaybackState copyWith({
    bool? isPlaying,
    bool? isPaused,
    String? currentText,
    int? currentPosition,
    int? totalLength,
    double? progress,
  }) {
    return TTSPlaybackState(
      isPlaying: isPlaying ?? this.isPlaying,
      isPaused: isPaused ?? this.isPaused,
      currentText: currentText ?? this.currentText,
      currentPosition: currentPosition ?? this.currentPosition,
      totalLength: totalLength ?? this.totalLength,
      progress: progress ?? this.progress,
    );
  }
}

class TTSPlaybackNotifier extends StateNotifier<TTSPlaybackState> {
  final Ref ref;

  TTSPlaybackNotifier(this.ref) : super(TTSPlaybackState());

  Future<void> playArticle(String text) async {
    final tts = ref.read(ttsServiceProvider);
    
    state = state.copyWith(
      isPlaying: true,
      isPaused: false,
      currentText: text,
      totalLength: text.length,
      currentPosition: 0,
      progress: 0.0,
    );

    await tts.speak(
      text,
      onProgress: (start, end) {
        state = state.copyWith(
          currentPosition: end,
          progress: end / state.totalLength,
        );
      },
      onComplete: () {
        state = state.copyWith(
          isPlaying: false,
          isPaused: false,
          progress: 1.0,
        );
      },
    );
  }

  Future<void> pause() async {
    final tts = ref.read(ttsServiceProvider);
    await tts.pause();
    state = state.copyWith(isPaused: true, isPlaying: false);
  }

  Future<void> resume() async {
    if (state.currentText != null) {
      await playArticle(state.currentText!.substring(state.currentPosition));
    }
  }

  Future<void> stop() async {
    final tts = ref.read(ttsServiceProvider);
    await tts.stop();
    state = TTSPlaybackState();
  }
}