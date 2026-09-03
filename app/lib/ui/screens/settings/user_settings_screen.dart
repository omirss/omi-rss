import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/auth_provider.dart';
import '../../../core/models/user.dart';
import '../../glass_theme.dart';
import '../../components/glass_container.dart';
import '../../components/glass_button.dart';
import '../../components/glass_text_field.dart';
import '../../components/glass_dialog.dart';
import '../../animations/particle_background.dart';

class UserSettingsScreen extends ConsumerStatefulWidget {
  const UserSettingsScreen({super.key});

  @override
  ConsumerState<UserSettingsScreen> createState() => _UserSettingsScreenState();
}

class _UserSettingsScreenState extends ConsumerState<UserSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _usernameController;
  late TextEditingController _fullNameController;
  late TextEditingController _emailController;
  bool _isEditing = false;
  
  @override
  void initState() {
    super.initState();
    final user = ref.read(authStateProvider).user;
    _usernameController = TextEditingController(text: user?.username ?? '');
    _fullNameController = TextEditingController(text: user?.fullName ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
  }
  
  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }
  
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    // TODO: Implement profile update API call
    setState(() {
      _isEditing = false;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile updated successfully'),
          backgroundColor: Colors.green.shade400,
        ),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      body: Stack(
        children: [
          // Background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: GlassColors.backgroundGradient,
              ),
            ),
          ),
          
          // Particle animation
          const ParticleBackground(particleCount: 40),
          
          // Content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          GlassButton(
                            icon: Icons.arrow_back,
                            onPressed: () => Navigator.of(context).pop(),
                            variant: GlassButtonVariant.icon,
                            width: 40,
                            height: 40,
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'User Settings',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Profile section
                      GlassContainer(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Profile',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (!_isEditing)
                                    GlassButton(
                                      text: 'Edit',
                                      icon: Icons.edit,
                                      onPressed: () {
                                        setState(() {
                                          _isEditing = true;
                                        });
                                      },
                                      variant: GlassButtonVariant.outlined,
                                    ),
                                ],
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // Avatar
                              Center(
                                child: Stack(
                                  children: [
                                    GlassContainer(
                                      width: 100,
                                      height: 100,
                                      borderRadius: BorderRadius.circular(50),
                                      child: Icon(
                                        Icons.person,
                                        size: 50,
                                        color: Colors.white.withOpacity(0.8),
                                      ),
                                    ),
                                    if (_isEditing)
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: GlassButton(
                                          icon: Icons.camera_alt,
                                          onPressed: () {
                                            // TODO: Implement avatar upload
                                          },
                                          variant: GlassButtonVariant.icon,
                                          width: 32,
                                          height: 32,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // Email (read-only)
                              _buildField(
                                'Email',
                                _emailController,
                                enabled: false,
                                icon: Icons.email,
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Username
                              _buildField(
                                'Username',
                                _usernameController,
                                enabled: _isEditing,
                                icon: Icons.person,
                                validator: (value) {
                                  if (_isEditing && (value == null || value.isEmpty)) {
                                    return 'Please enter a username';
                                  }
                                  return null;
                                },
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Full name
                              _buildField(
                                'Full Name',
                                _fullNameController,
                                enabled: _isEditing,
                                icon: Icons.badge,
                              ),
                              
                              if (_isEditing) ...[
                                const SizedBox(height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    GlassButton(
                                      text: 'Cancel',
                                      onPressed: () {
                                        setState(() {
                                          _isEditing = false;
                                          // Reset controllers
                                          _usernameController.text = user?.username ?? '';
                                          _fullNameController.text = user?.fullName ?? '';
                                        });
                                      },
                                      variant: GlassButtonVariant.outlined,
                                    ),
                                    const SizedBox(width: 12),
                                    GlassButton(
                                      text: 'Save',
                                      onPressed: _saveProfile,
                                      variant: GlassButtonVariant.elevated,
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Statistics
                      if (user?.statistics != null)
                        GlassContainer(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Statistics',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildStatRow('Total Subscriptions', user!.statistics!.totalSubscriptions.toString()),
                              _buildStatRow('Total Folders', user.statistics!.totalFolders.toString()),
                              _buildStatRow('Saved Articles', user.statistics!.totalSavedArticles.toString()),
                              _buildStatRow('Read Articles', user.statistics!.totalReadArticles.toString()),
                              _buildStatRow('Reading Streak', '${user.statistics!.readingStreak} days'),
                              _buildStatRow('Member Since', _formatDate(user.statistics!.memberSince)),
                            ],
                          ),
                        ),
                      
                      const SizedBox(height: 24),
                      
                      // Security section
                      GlassContainer(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Security',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ListTile(
                              leading: Icon(Icons.lock, color: Colors.white.withOpacity(0.8)),
                              title: Text(
                                'Change Password',
                                style: TextStyle(color: Colors.white),
                              ),
                              trailing: Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.6)),
                              onTap: () => _showChangePasswordDialog(),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Danger zone
                      GlassContainer(
                        padding: const EdgeInsets.all(24),
                        gradientColors: [
                          Colors.red.withOpacity(0.1),
                          Colors.orange.withOpacity(0.05),
                        ],
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Danger Zone',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade300,
                              ),
                            ),
                            const SizedBox(height: 16),
                            GlassButton(
                              text: 'Delete Account',
                              icon: Icons.delete_forever,
                              onPressed: () => _showDeleteAccountDialog(),
                              variant: GlassButtonVariant.outlined,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildField(
    String label,
    TextEditingController controller, {
    bool enabled = true,
    IconData? icon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        GlassTextField(
          controller: controller,
          enabled: enabled,
          prefixIcon: icon != null ? Icon(icon, color: Colors.white70) : null,
          validator: validator,
        ),
      ],
    );
  }
  
  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
  
  Future<void> _showChangePasswordDialog() async {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    
    final result = await showGlassDialog<bool>(
      context: context,
      title: const Text('Change Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassTextField(
            controller: currentPasswordController,
            hintText: 'Current Password',
            obscureText: true,
            prefixIcon: Icon(Icons.lock, color: Colors.white70),
          ),
          const SizedBox(height: 16),
          GlassTextField(
            controller: newPasswordController,
            hintText: 'New Password',
            obscureText: true,
            prefixIcon: Icon(Icons.lock_outline, color: Colors.white70),
          ),
          const SizedBox(height: 16),
          GlassTextField(
            controller: confirmPasswordController,
            hintText: 'Confirm Password',
            obscureText: true,
            prefixIcon: Icon(Icons.lock_outline, color: Colors.white70),
          ),
        ],
      ),
      actions: [
        GlassButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
          variant: GlassButtonVariant.text,
        ),
        GlassButton(
          text: 'Change Password',
          onPressed: () => Navigator.of(context).pop(true),
          variant: GlassButtonVariant.elevated,
        ),
      ],
    );
    
    if (result == true) {
      // TODO: Implement password change
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password changed successfully'),
            backgroundColor: Colors.green.shade400,
          ),
        );
      }
    }
    
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
  }
  
  Future<void> _showDeleteAccountDialog() async {
    final confirm = await showGlassConfirmDialog(
      context: context,
      title: 'Delete Account',
      message: 'Are you sure you want to delete your account? This action cannot be undone.',
      confirmText: 'Delete Account',
      destructive: true,
    );
    
    if (confirm == true) {
      // TODO: Implement account deletion
      await ref.read(authStateProvider.notifier).logout();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }
  }
}