import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/translation_provider.dart';
import '../../ui/glass_theme.dart';
import '../../ui/components/glass_container.dart';
import '../../ui/components/glass_button.dart';
import '../../ui/components/glass_dialog.dart';
import '../../ui/components/glass_snack_bar.dart';
import 'translation_service.dart';

class TranslationControls extends ConsumerWidget {
  final String articleId;
  final VoidCallback? onTranslationComplete;
  
  const TranslationControls({
    super.key,
    required this.articleId,
    this.onTranslationComplete,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(translationSettingsProvider);
    final supportedLanguages = ref.watch(supportedLanguagesProvider);
    
    return GlassContainer(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Language selector
          Expanded(
            child: supportedLanguages.when(
              data: (languages) => _buildLanguageSelector(
                context,
                ref,
                languages,
                settings.preferredLanguage,
              ),
              loading: () => const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (_, __) => const Text(
                'Failed to load languages',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ),
          const SizedBox(width: 8),
          
          // Translate button
          GlassButton(
            icon: Icons.translate,
            text: 'Translate',
            onPressed: settings.preferredLanguage != null
              ? () => _translateArticle(context, ref)
              : null,
            variant: GlassButtonVariant.elevated,
          ),
          const SizedBox(width: 8),
          
          // Settings button
          GlassButton(
            icon: Icons.settings,
            onPressed: () => _showTranslationSettings(context, ref),
            variant: GlassButtonVariant.icon,
          ),
        ],
      ),
    );
  }
  
  Widget _buildLanguageSelector(
    BuildContext context,
    WidgetRef ref,
    List<SupportedLanguage> languages,
    String? selectedLanguage,
  ) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButton<String>(
        value: selectedLanguage,
        hint: Text(
          'Select language',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        isExpanded: true,
        underline: const SizedBox(),
        dropdownColor: GlassTheme.surfaceColor,
        icon: Icon(Icons.arrow_drop_down, color: Colors.white.withOpacity(0.7)),
        items: languages.map((lang) {
          return DropdownMenuItem(
            value: lang.code,
            child: Row(
              children: [
                if (lang.isRTL)
                  const Icon(Icons.format_textdirection_r_to_l, size: 16)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Text(
                  '${lang.name} (${lang.nativeName})',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: (value) {
          ref.read(translationSettingsProvider.notifier).setPreferredLanguage(value);
        },
      ),
    );
  }
  
  Future<void> _translateArticle(BuildContext context, WidgetRef ref) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: GlassContainer(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              Text(
                'Translating...',
                style: TextStyle(color: Colors.white.withOpacity(0.9)),
              ),
            ],
          ),
        ),
      ),
    );
    
    try {
      // Perform translation
      // This would get the article and translate it
      await Future.delayed(const Duration(seconds: 2)); // Simulated
      
      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog
        context.showSuccessSnackBar('Article translated successfully');
        onTranslationComplete?.call();
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog
        context.showErrorSnackBar('Translation failed: ${e.toString()}');
      }
    }
  }
  
  void _showTranslationSettings(BuildContext context, WidgetRef ref) {
    showGlassDialog(
      context: context,
      title: const Text('Translation Settings'),
      content: const TranslationSettingsDialog(),
      size: GlassDialogSize.large,
    );
  }
}

class TranslationSettingsDialog extends ConsumerWidget {
  const TranslationSettingsDialog({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(translationSettingsProvider);
    final settingsNotifier = ref.read(translationSettingsProvider.notifier);
    
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Translation options
          Text(
            'Translation Options',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          SwitchListTile(
            title: Text(
              'Auto-detect language',
              style: TextStyle(color: Colors.white.withOpacity(0.9)),
            ),
            subtitle: Text(
              'Automatically detect the source language',
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
            ),
            value: settings.autoDetectLanguage,
            onChanged: (_) => settingsNotifier.toggleAutoDetectLanguage(),
            activeColor: Theme.of(context).colorScheme.primary,
          ),
          
          SwitchListTile(
            title: Text(
              'Translate titles',
              style: TextStyle(color: Colors.white.withOpacity(0.9)),
            ),
            value: settings.translateTitles,
            onChanged: (_) => settingsNotifier.toggleTranslateTitles(),
            activeColor: Theme.of(context).colorScheme.primary,
          ),
          
          SwitchListTile(
            title: Text(
              'Translate content',
              style: TextStyle(color: Colors.white.withOpacity(0.9)),
            ),
            value: settings.translateContent,
            onChanged: (_) => settingsNotifier.toggleTranslateContent(),
            activeColor: Theme.of(context).colorScheme.primary,
          ),
          
          SwitchListTile(
            title: Text(
              'Translate summaries',
              style: TextStyle(color: Colors.white.withOpacity(0.9)),
            ),
            value: settings.translateSummaries,
            onChanged: (_) => settingsNotifier.toggleTranslateSummaries(),
            activeColor: Theme.of(context).colorScheme.primary,
          ),
          
          SwitchListTile(
            title: Text(
              'Show original text',
              style: TextStyle(color: Colors.white.withOpacity(0.9)),
            ),
            subtitle: Text(
              'Display original text alongside translation',
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
            ),
            value: settings.showOriginalText,
            onChanged: (_) => settingsNotifier.toggleShowOriginalText(),
            activeColor: Theme.of(context).colorScheme.primary,
          ),
          
          SwitchListTile(
            title: Text(
              'Cache translations',
              style: TextStyle(color: Colors.white.withOpacity(0.9)),
            ),
            subtitle: Text(
              'Save translations for offline viewing',
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
            ),
            value: settings.cacheTranslations,
            onChanged: (_) => settingsNotifier.toggleCacheTranslations(),
            activeColor: Theme.of(context).colorScheme.primary,
          ),
          
          const SizedBox(height: 24),
          
          // Provider configuration
          Text(
            'Translation Provider',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          GlassButton(
            text: 'Configure Google Translate',
            icon: Icons.g_translate,
            onPressed: () => _showProviderConfig(context, ref, 'google'),
            variant: GlassButtonVariant.text,
            width: double.infinity,
          ),
          const SizedBox(height: 8),
          
          GlassButton(
            text: 'Configure LibreTranslate',
            icon: Icons.translate,
            onPressed: () => _showProviderConfig(context, ref, 'libre'),
            variant: GlassButtonVariant.text,
            width: double.infinity,
          ),
          
          const SizedBox(height: 24),
          
          // Actions
          Row(
            children: [
              Expanded(
                child: GlassButton(
                  text: 'Clear Cache',
                  icon: Icons.delete_sweep,
                  onPressed: () {
                    ref.read(translationManagerProvider).clearCache();
                    context.showSuccessSnackBar('Translation cache cleared');
                  },
                  variant: GlassButtonVariant.text,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GlassButton(
                  text: 'Close',
                  onPressed: () => Navigator.pop(context),
                  variant: GlassButtonVariant.elevated,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  void _showProviderConfig(BuildContext context, WidgetRef ref, String provider) {
    showGlassDialog(
      context: context,
      title: Text(provider == 'google' ? 'Google Translate' : 'LibreTranslate'),
      content: provider == 'google'
        ? const GoogleTranslateConfig()
        : const LibreTranslateConfig(),
    );
  }
}

class GoogleTranslateConfig extends ConsumerStatefulWidget {
  const GoogleTranslateConfig({super.key});
  
  @override
  ConsumerState<GoogleTranslateConfig> createState() => _GoogleTranslateConfigState();
}

class _GoogleTranslateConfigState extends ConsumerState<GoogleTranslateConfig> {
  final _apiKeyController = TextEditingController();
  
  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _apiKeyController,
          decoration: InputDecoration(
            labelText: 'API Key',
            hintText: 'Enter your Google Cloud API key',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.9)),
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
          ),
          style: const TextStyle(color: Colors.white),
          obscureText: true,
        ),
        const SizedBox(height: 16),
        Text(
          'To get an API key:\n'
          '1. Go to Google Cloud Console\n'
          '2. Enable Translation API\n'
          '3. Create credentials',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: GlassButton(
                text: 'Cancel',
                onPressed: () => Navigator.pop(context),
                variant: GlassButtonVariant.text,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: GlassButton(
                text: 'Save',
                onPressed: () async {
                  final apiKey = _apiKeyController.text.trim();
                  if (apiKey.isNotEmpty) {
                    await ref.read(translationManagerProvider).setupGoogleTranslate(apiKey);
                    if (context.mounted) {
                      Navigator.pop(context);
                      context.showSuccessSnackBar('Google Translate configured');
                    }
                  }
                },
                variant: GlassButtonVariant.elevated,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class LibreTranslateConfig extends ConsumerStatefulWidget {
  const LibreTranslateConfig({super.key});
  
  @override
  ConsumerState<LibreTranslateConfig> createState() => _LibreTranslateConfigState();
}

class _LibreTranslateConfigState extends ConsumerState<LibreTranslateConfig> {
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  
  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _urlController,
          decoration: InputDecoration(
            labelText: 'Server URL',
            hintText: 'https://libretranslate.com',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.9)),
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
          ),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _apiKeyController,
          decoration: InputDecoration(
            labelText: 'API Key (Optional)',
            hintText: 'Leave empty for public instances',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.9)),
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
          ),
          style: const TextStyle(color: Colors.white),
          obscureText: true,
        ),
        const SizedBox(height: 16),
        Text(
          'LibreTranslate is an open-source translation API.\n'
          'You can use the public instance or self-host.',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: GlassButton(
                text: 'Cancel',
                onPressed: () => Navigator.pop(context),
                variant: GlassButtonVariant.text,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: GlassButton(
                text: 'Save',
                onPressed: () async {
                  final url = _urlController.text.trim();
                  final apiKey = _apiKeyController.text.trim();
                  if (url.isNotEmpty) {
                    await ref.read(translationManagerProvider).setupLibreTranslate(
                      url,
                      apiKey: apiKey.isNotEmpty ? apiKey : null,
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      context.showSuccessSnackBar('LibreTranslate configured');
                    }
                  }
                },
                variant: GlassButtonVariant.elevated,
              ),
            ),
          ],
        ),
      ],
    );
  }
}