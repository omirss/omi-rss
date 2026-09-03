import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/tts_provider.dart';
import '../../ui/glass_theme.dart';
import '../../ui/components/glass_container.dart';
import '../../ui/components/glass_button.dart';
import '../../ui/components/glass_dialog.dart';

class TTSControls extends ConsumerWidget {
  final String articleText;
  
  const TTSControls({
    super.key,
    required this.articleText,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackState = ref.watch(ttsPlaybackProvider);
    final ttsSettings = ref.watch(ttsSettingsProvider);

    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Play/Pause button
          GlassButton(
            icon: playbackState.isPlaying 
              ? Icons.pause 
              : Icons.play_arrow,
            onPressed: () => _togglePlayback(ref, playbackState),
            variant: GlassButtonVariant.icon,
            width: 40,
            height: 40,
          ),
          const SizedBox(width: 8),
          
          // Stop button
          if (playbackState.isPlaying || playbackState.isPaused) ...[
            GlassButton(
              icon: Icons.stop,
              onPressed: () => ref.read(ttsPlaybackProvider.notifier).stop(),
              variant: GlassButtonVariant.icon,
              width: 40,
              height: 40,
            ),
            const SizedBox(width: 8),
          ],
          
          // Progress indicator
          if (playbackState.isPlaying || playbackState.isPaused) ...[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playbackState.isPlaying ? 'Speaking...' : 'Paused',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: playbackState.progress,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ] else ...[
            Expanded(
              child: Text(
                'Text-to-Speech',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
            ),
          ],
          
          // Speed control
          PopupMenuButton<double>(
            icon: Icon(
              Icons.speed,
              color: Colors.white.withOpacity(0.8),
            ),
            tooltip: 'Speech rate',
            onSelected: (rate) async {
              await ref.read(ttsSettingsProvider.notifier).setSpeechRate(rate);
            },
            itemBuilder: (context) => [
              for (final rate in [0.25, 0.5, 0.75, 1.0])
                PopupMenuItem(
                  value: rate,
                  child: Row(
                    children: [
                      if (ttsSettings.speechRate == rate)
                        const Icon(Icons.check, size: 16)
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 8),
                      Text('${(rate * 2).toStringAsFixed(1)}x'),
                    ],
                  ),
                ),
            ],
          ),
          
          // Settings button
          GlassButton(
            icon: Icons.settings,
            onPressed: () => _showTTSSettings(context, ref),
            variant: GlassButtonVariant.icon,
            width: 40,
            height: 40,
          ),
        ],
      ),
    );
  }

  void _togglePlayback(WidgetRef ref, TTSPlaybackState playbackState) {
    if (playbackState.isPlaying) {
      ref.read(ttsPlaybackProvider.notifier).pause();
    } else if (playbackState.isPaused) {
      ref.read(ttsPlaybackProvider.notifier).resume();
    } else {
      ref.read(ttsPlaybackProvider.notifier).playArticle(articleText);
    }
  }

  void _showTTSSettings(BuildContext context, WidgetRef ref) {
    showGlassDialog(
      context: context,
      title: const Text('Text-to-Speech Settings'),
      content: const TTSSettingsDialog(),
      size: GlassDialogSize.medium,
    );
  }
}

class TTSSettingsDialog extends ConsumerStatefulWidget {
  const TTSSettingsDialog({super.key});

  @override
  ConsumerState<TTSSettingsDialog> createState() => _TTSSettingsDialogState();
}

class _TTSSettingsDialogState extends ConsumerState<TTSSettingsDialog> {
  List<String> _availableLanguages = [];
  List<Map<String, String>> _availableVoices = [];

  @override
  void initState() {
    super.initState();
    _loadAvailableOptions();
  }

  Future<void> _loadAvailableOptions() async {
    final tts = ref.read(ttsServiceProvider);
    final languages = await tts.getAvailableLanguages();
    final voices = await tts.getAvailableVoices();
    
    if (mounted) {
      setState(() {
        _availableLanguages = languages;
        _availableVoices = voices;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(ttsSettingsProvider);
    final settingsNotifier = ref.read(ttsSettingsProvider.notifier);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Speech Rate
          _buildSliderSetting(
            title: 'Speech Rate',
            value: settings.speechRate,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            label: '${(settings.speechRate * 2).toStringAsFixed(1)}x',
            onChanged: (value) => settingsNotifier.setSpeechRate(value),
          ),
          const SizedBox(height: 16),
          
          // Volume
          _buildSliderSetting(
            title: 'Volume',
            value: settings.volume,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            label: '${(settings.volume * 100).toInt()}%',
            onChanged: (value) => settingsNotifier.setVolume(value),
          ),
          const SizedBox(height: 16),
          
          // Pitch
          _buildSliderSetting(
            title: 'Pitch',
            value: settings.pitch,
            min: 0.5,
            max: 2.0,
            divisions: 15,
            label: settings.pitch.toStringAsFixed(1),
            onChanged: (value) => settingsNotifier.setPitch(value),
          ),
          const SizedBox(height: 16),
          
          // Language selection
          if (_availableLanguages.isNotEmpty) ...[
            Text(
              'Language',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<String>(
                value: settings.language ?? _availableLanguages.first,
                isExpanded: true,
                dropdownColor: Theme.of(context).colorScheme.surface,
                underline: const SizedBox(),
                items: _availableLanguages.map((lang) {
                  return DropdownMenuItem(
                    value: lang,
                    child: Text(
                      lang,
                      style: const TextStyle(color: Colors.white),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    settingsNotifier.setLanguage(value);
                  }
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // Toggle options
          SwitchListTile(
            title: Text(
              'Auto-play on article open',
              style: TextStyle(color: Colors.white.withOpacity(0.9)),
            ),
            value: settings.autoPlay,
            onChanged: (_) => settingsNotifier.toggleAutoPlay(),
            activeColor: Theme.of(context).colorScheme.primary,
          ),
          SwitchListTile(
            title: Text(
              'Highlight current text',
              style: TextStyle(color: Colors.white.withOpacity(0.9)),
            ),
            value: settings.highlightText,
            onChanged: (_) => settingsNotifier.toggleHighlightText(),
            activeColor: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          
          // Close button
          SizedBox(
            width: double.infinity,
            child: GlassButton(
              text: 'Close',
              onPressed: () => Navigator.pop(context),
              variant: GlassButtonVariant.elevated,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderSetting({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: label,
          onChanged: onChanged,
          activeColor: Theme.of(context).colorScheme.primary,
          inactiveColor: Colors.white.withOpacity(0.3),
        ),
      ],
    );
  }
}