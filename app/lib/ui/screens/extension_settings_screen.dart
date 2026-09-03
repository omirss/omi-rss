import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rss_glassmorphism_reader/core/theme/glass_theme.dart';
import 'package:rss_glassmorphism_reader/core/services/extension_service.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_container.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_switch.dart';

// Extension settings provider
final extensionSettingsProvider = StateNotifierProvider<ExtensionSettingsNotifier, ExtensionSettings>((ref) {
  return ExtensionSettingsNotifier();
});

class ExtensionSettings {
  final bool bypassEnabled;
  final bool aiEnabled;
  final bool notificationsEnabled;
  final bool autoDetectFeeds;
  final bool showBadgeCount;
  final int updateInterval;
  final List<String> bypassDomains;

  ExtensionSettings({
    this.bypassEnabled = false,
    this.aiEnabled = true,
    this.notificationsEnabled = true,
    this.autoDetectFeeds = true,
    this.showBadgeCount = true,
    this.updateInterval = 15,
    this.bypassDomains = const [],
  });

  ExtensionSettings copyWith({
    bool? bypassEnabled,
    bool? aiEnabled,
    bool? notificationsEnabled,
    bool? autoDetectFeeds,
    bool? showBadgeCount,
    int? updateInterval,
    List<String>? bypassDomains,
  }) {
    return ExtensionSettings(
      bypassEnabled: bypassEnabled ?? this.bypassEnabled,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      autoDetectFeeds: autoDetectFeeds ?? this.autoDetectFeeds,
      showBadgeCount: showBadgeCount ?? this.showBadgeCount,
      updateInterval: updateInterval ?? this.updateInterval,
      bypassDomains: bypassDomains ?? this.bypassDomains,
    );
  }
}

class ExtensionSettingsNotifier extends StateNotifier<ExtensionSettings> {
  ExtensionSettingsNotifier() : super(ExtensionSettings());

  void toggleBypass(bool enabled) {
    state = state.copyWith(bypassEnabled: enabled);
  }

  void toggleAI(bool enabled) {
    state = state.copyWith(aiEnabled: enabled);
  }

  void toggleNotifications(bool enabled) {
    state = state.copyWith(notificationsEnabled: enabled);
  }

  void toggleAutoDetect(bool enabled) {
    state = state.copyWith(autoDetectFeeds: enabled);
  }

  void toggleBadgeCount(bool enabled) {
    state = state.copyWith(showBadgeCount: enabled);
  }

  void setUpdateInterval(int minutes) {
    state = state.copyWith(updateInterval: minutes);
  }

  void addBypassDomain(String domain) {
    state = state.copyWith(
      bypassDomains: [...state.bypassDomains, domain],
    );
  }

  void removeBypassDomain(String domain) {
    state = state.copyWith(
      bypassDomains: state.bypassDomains.where((d) => d != domain).toList(),
    );
  }
}

class ExtensionSettingsScreen extends ConsumerStatefulWidget {
  const ExtensionSettingsScreen({super.key});

  @override
  ConsumerState<ExtensionSettingsScreen> createState() => _ExtensionSettingsScreenState();
}

class _ExtensionSettingsScreenState extends ConsumerState<ExtensionSettingsScreen> {
  final TextEditingController _domainController = TextEditingController();

  @override
  void dispose() {
    _domainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final settings = ref.watch(extensionSettingsProvider);
    final notifier = ref.read(extensionSettingsProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Extension Settings',
          style: theme.textTheme.titleLarge,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // General Settings
          _buildSection(
            theme,
            title: 'General',
            children: [
              _SettingTile(
                title: 'Auto-detect RSS feeds',
                subtitle: 'Automatically detect feeds on visited pages',
                value: settings.autoDetectFeeds,
                onChanged: notifier.toggleAutoDetect,
              ),
              _SettingTile(
                title: 'Show badge count',
                subtitle: 'Display unread article count on extension icon',
                value: settings.showBadgeCount,
                onChanged: notifier.toggleBadgeCount,
              ),
              _SettingTile(
                title: 'Enable notifications',
                subtitle: 'Get notified about new articles',
                value: settings.notificationsEnabled,
                onChanged: notifier.toggleNotifications,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // AI Settings
          _buildSection(
            theme,
            title: 'AI Analysis',
            children: [
              _SettingTile(
                title: 'Enable AI features',
                subtitle: 'Use local AI for article analysis',
                value: settings.aiEnabled,
                onChanged: notifier.toggleAI,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Update Interval
          _buildSection(
            theme,
            title: 'Feed Updates',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Update interval',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Check for new articles every ${settings.updateInterval} minutes',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white60,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Slider(
                      value: settings.updateInterval.toDouble(),
                      min: 5,
                      max: 60,
                      divisions: 11,
                      label: '${settings.updateInterval} min',
                      activeColor: theme.primaryGradient.colors.first,
                      onChanged: (value) {
                        notifier.setUpdateInterval(value.round());
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Paywall Bypass Settings
          _buildSection(
            theme,
            title: 'Paywall Bypass',
            isWarning: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: GlassContainer(
                  gradient: LinearGradient(
                    colors: [
                      Colors.orange.withOpacity(0.2),
                      Colors.red.withOpacity(0.2),
                    ],
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning,
                        color: Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Use responsibly. Support journalism by subscribing.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _SettingTile(
                title: 'Enable paywall bypass',
                subtitle: 'Attempt to bypass paywalls on supported sites',
                value: settings.bypassEnabled,
                onChanged: notifier.toggleBypass,
              ),
              if (settings.bypassEnabled) ...[
                const Divider(color: Colors.white10),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Custom domains',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add domains where bypass should be attempted',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white60,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _domainController,
                              style: theme.textTheme.bodyMedium,
                              decoration: InputDecoration(
                                hintText: 'example.com',
                                hintStyle: TextStyle(color: Colors.white30),
                                filled: true,
                                fillColor: Colors.white10,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            onPressed: () {
                              if (_domainController.text.isNotEmpty) {
                                notifier.addBypassDomain(_domainController.text);
                                _domainController.clear();
                              }
                            },
                            icon: Icon(
                              Icons.add_circle,
                              color: theme.primaryGradient.colors.first,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ...settings.bypassDomains.map((domain) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassContainer(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.language,
                                size: 16,
                                color: Colors.white60,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  domain,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  size: 20,
                                  color: Colors.red,
                                ),
                                onPressed: () {
                                  notifier.removeBypassDomain(domain);
                                },
                              ),
                            ],
                          ),
                        ),
                      )).toList(),
                    ],
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 24),

          // About Section
          _buildSection(
            theme,
            title: 'About',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RSS Glassmorphism Reader Extension',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Version 1.0.0',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white60,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'A beautiful RSS reader with glassmorphism design, AI analysis, and advanced features.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    GlassTheme theme, {
    required String title,
    required List<Widget> children,
    bool isWarning = false,
  }) {
    return GlassContainer(
      gradient: isWarning
          ? LinearGradient(
              colors: [
                Colors.orange.withOpacity(0.1),
                Colors.red.withOpacity(0.1),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: isWarning ? Colors.orange : null,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SettingTile extends ConsumerWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    return ListTile(
      title: Text(
        title,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: Colors.white60,
        ),
      ),
      trailing: GlassSwitch(
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}