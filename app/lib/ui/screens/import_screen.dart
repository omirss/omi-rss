import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import '../glass_theme.dart';
import '../components/glass_container.dart';
import '../components/glass_button.dart';
import '../components/glass_app_bar.dart';
import '../components/glass_text_field.dart';
import '../components/glass_snack_bar.dart';
import '../components/glass_dialog.dart';
import '../../providers/import_provider.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  int _selectedTab = 0;
  
  // Pocket API fields
  final _pocketConsumerKeyController = TextEditingController();
  final _pocketAccessTokenController = TextEditingController();
  
  // Instapaper API fields
  final _instapaperUsernameController = TextEditingController();
  final _instapaperPasswordController = TextEditingController();
  
  @override
  void dispose() {
    _pocketConsumerKeyController.dispose();
    _pocketAccessTokenController.dispose();
    _instapaperUsernameController.dispose();
    _instapaperPasswordController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final importStatus = ref.watch(importStatusProvider);
    
    return Scaffold(
      backgroundColor: GlassTheme.backgroundColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              GlassTheme.primaryColor.withOpacity(0.1),
              GlassTheme.accentColor.withOpacity(0.1),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App Bar
              GlassAppBar(
                title: 'Import Articles',
                leading: GlassButton(
                  icon: Icons.arrow_back,
                  onPressed: () => Navigator.of(context).pop(),
                  variant: GlassButtonVariant.icon,
                ),
              ),
              
              // Tab selector
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: GlassButton(
                        text: 'Pocket',
                        icon: Icons.bookmark,
                        onPressed: () => setState(() => _selectedTab = 0),
                        variant: _selectedTab == 0 
                          ? GlassButtonVariant.elevated 
                          : GlassButtonVariant.text,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: GlassButton(
                        text: 'Instapaper',
                        icon: Icons.article,
                        onPressed: () => setState(() => _selectedTab = 1),
                        variant: _selectedTab == 1 
                          ? GlassButtonVariant.elevated 
                          : GlassButtonVariant.text,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Import status
                      if (importStatus.state != ImportState.idle) ...[
                        _buildImportStatus(importStatus),
                        const SizedBox(height: 24),
                      ],
                      
                      // Tab content
                      if (_selectedTab == 0)
                        _buildPocketImport()
                      else
                        _buildInstapaperImport(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildImportStatus(ImportStatus status) {
    IconData icon;
    Color color;
    
    switch (status.state) {
      case ImportState.importing:
      case ImportState.processing:
        icon = Icons.sync;
        color = Colors.blue;
        break;
      case ImportState.completed:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case ImportState.error:
        icon = Icons.error;
        color = Colors.red;
        break;
      default:
        icon = Icons.info;
        color = Colors.white;
    }
    
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Icon(icon, color: color, size: 48)
            .animate(
              onPlay: (controller) {
                if (status.state == ImportState.importing || 
                    status.state == ImportState.processing) {
                  controller.repeat();
                }
              },
            )
            .rotate(duration: 2.seconds),
          const SizedBox(height: 16),
          Text(
            status.currentStep ?? 'Ready to import',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (status.totalArticles > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${status.processedArticles} / ${status.totalArticles} articles',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: status.progress,
              backgroundColor: Colors.white.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ],
          if (status.errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              status.errorMessage!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildPocketImport() {
    return Column(
      children: [
        // File import
        GlassContainer(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.file_upload, color: Colors.white.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  Text(
                    'Import from File',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Export your Pocket data from getpocket.com/export and upload the HTML file',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              GlassButton(
                text: 'Choose File',
                icon: Icons.folder_open,
                onPressed: _importPocketFile,
                variant: GlassButtonVariant.elevated,
                width: double.infinity,
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // API import
        GlassContainer(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.cloud_download, color: Colors.white.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  Text(
                    'Import from API',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Use your Pocket API credentials to import directly',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              GlassTextField(
                controller: _pocketConsumerKeyController,
                labelText: 'Consumer Key',
                hintText: 'Enter your Pocket consumer key',
                prefixIcon: Icons.key,
              ),
              const SizedBox(height: 16),
              GlassTextField(
                controller: _pocketAccessTokenController,
                labelText: 'Access Token',
                hintText: 'Enter your Pocket access token',
                prefixIcon: Icons.lock,
                obscureText: true,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      text: 'How to get API keys',
                      icon: Icons.help_outline,
                      onPressed: () => _showApiHelpDialog('Pocket'),
                      variant: GlassButtonVariant.text,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GlassButton(
                      text: 'Import',
                      icon: Icons.download,
                      onPressed: _importPocketApi,
                      variant: GlassButtonVariant.elevated,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildInstapaperImport() {
    return Column(
      children: [
        // File import
        GlassContainer(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.file_upload, color: Colors.white.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  Text(
                    'Import from File',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Export your Instapaper data from instapaper.com/user and upload the CSV or HTML file',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              GlassButton(
                text: 'Choose File',
                icon: Icons.folder_open,
                onPressed: _importInstapaperFile,
                variant: GlassButtonVariant.elevated,
                width: double.infinity,
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // API import
        GlassContainer(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.cloud_download, color: Colors.white.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  Text(
                    'Import from API',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Use your Instapaper credentials to import directly',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              GlassTextField(
                controller: _instapaperUsernameController,
                labelText: 'Username/Email',
                hintText: 'Enter your Instapaper username',
                prefixIcon: Icons.person,
              ),
              const SizedBox(height: 16),
              GlassTextField(
                controller: _instapaperPasswordController,
                labelText: 'Password',
                hintText: 'Enter your Instapaper password',
                prefixIcon: Icons.lock,
                obscureText: true,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      text: 'How to enable API',
                      icon: Icons.help_outline,
                      onPressed: () => _showApiHelpDialog('Instapaper'),
                      variant: GlassButtonVariant.text,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GlassButton(
                      text: 'Import',
                      icon: Icons.download,
                      onPressed: _importInstapaperApi,
                      variant: GlassButtonVariant.elevated,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Future<void> _importPocketFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['html', 'htm'],
      );
      
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        await ref.read(importManagerProvider).importFromPocketFile(file);
        
        if (mounted) {
          context.showSuccessSnackBar('Pocket articles imported successfully');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to import: ${e.toString()}');
      }
    }
  }
  
  Future<void> _importPocketApi() async {
    final consumerKey = _pocketConsumerKeyController.text.trim();
    final accessToken = _pocketAccessTokenController.text.trim();
    
    if (consumerKey.isEmpty || accessToken.isEmpty) {
      context.showErrorSnackBar('Please enter both Consumer Key and Access Token');
      return;
    }
    
    try {
      await ref.read(importManagerProvider).importFromPocketApi(
        consumerKey,
        accessToken,
      );
      
      if (mounted) {
        context.showSuccessSnackBar('Pocket articles imported successfully');
        _pocketConsumerKeyController.clear();
        _pocketAccessTokenController.clear();
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to import: ${e.toString()}');
      }
    }
  }
  
  Future<void> _importInstapaperFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['html', 'htm', 'csv'],
      );
      
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        await ref.read(importManagerProvider).importFromInstapaperFile(file);
        
        if (mounted) {
          context.showSuccessSnackBar('Instapaper articles imported successfully');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to import: ${e.toString()}');
      }
    }
  }
  
  Future<void> _importInstapaperApi() async {
    final username = _instapaperUsernameController.text.trim();
    final password = _instapaperPasswordController.text.trim();
    
    if (username.isEmpty || password.isEmpty) {
      context.showErrorSnackBar('Please enter both username and password');
      return;
    }
    
    try {
      await ref.read(importManagerProvider).importFromInstapaperApi(
        username,
        password,
      );
      
      if (mounted) {
        context.showSuccessSnackBar('Instapaper articles imported successfully');
        _instapaperUsernameController.clear();
        _instapaperPasswordController.clear();
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to import: ${e.toString()}');
      }
    }
  }
  
  void _showApiHelpDialog(String service) {
    String content;
    
    if (service == 'Pocket') {
      content = '''
To get your Pocket API credentials:

1. Go to getpocket.com/developer
2. Create a new app
3. Copy the Consumer Key
4. Generate an Access Token using the OAuth flow
5. Enter both keys above

Note: The Access Token is specific to your account and grants read access to your saved articles.
      ''';
    } else {
      content = '''
To enable Instapaper API access:

1. Instapaper requires a subscription for API access
2. Go to instapaper.com/user
3. Enable "Full API Access" in settings
4. Use your regular login credentials above

Note: Your password is used for authentication and is not stored.
      ''';
    }
    
    showGlassDialog(
      context: context,
      title: Text('$service API Setup'),
      content: Text(
        content,
        style: TextStyle(
          color: Colors.white.withOpacity(0.8),
          fontSize: 14,
        ),
      ),
      actions: [
        GlassButton(
          text: 'Got it',
          onPressed: () => Navigator.pop(context),
          variant: GlassButtonVariant.elevated,
        ),
      ],
    );
  }
}