import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/api_config.dart';
import '../../../core/models/user.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_service.dart';
import '../../components/glass_button.dart';
import '../../components/glass_container.dart';
import '../../components/glass_dialog.dart';
import '../../components/glass_snack_bar.dart';
import '../../components/glass_text_field.dart';
import '../../tokens/glass_tokens.dart';
import '../glass_screen.dart';

class UserSettingsScreen extends ConsumerStatefulWidget {
  const UserSettingsScreen({super.key});

  @override
  ConsumerState<UserSettingsScreen> createState() => _UserSettingsScreenState();
}

class _UserSettingsScreenState extends ConsumerState<UserSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _usernameController;
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _emailController;
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _usernameController = TextEditingController(text: user?.username ?? '');
    final fullName = user?.fullName ?? '';
    final nameParts = fullName.trim().split(' ');
    _firstNameController =
        TextEditingController(text: nameParts.isNotEmpty ? nameParts.first : '');
    _lastNameController = TextEditingController(
        text: nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '');
    _emailController = TextEditingController(text: user?.email ?? '');
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final updated = await ref.read(apiServiceProvider).updateUser({
        'username': _usernameController.text.trim(),
        if (_firstNameController.text.trim().isNotEmpty)
          'firstName': _firstNameController.text.trim(),
        if (_lastNameController.text.trim().isNotEmpty)
          'lastName': _lastNameController.text.trim(),
      });
      await ref.read(authProvider.notifier).updateUser(updated);
      setState(() => _isEditing = false);
      if (mounted) {
        context.showSuccessSnackBar('Profile updated successfully');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to update profile: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _uploadAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final file = result?.files.single;
      if (file == null) return;

      final api = ref.read(apiServiceProvider);
      final User updated;
      if (file.bytes != null) {
        updated = await api.uploadAvatarBytes(file.bytes!, file.name);
      } else if (file.path != null) {
        updated = await api.uploadAvatar(file.path!, file.name);
      } else {
        return;
      }
      await ref.read(authProvider.notifier).updateUser(updated);
      if (mounted) {
        context.showSuccessSnackBar('Avatar updated');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to upload avatar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final tokens = screenTokensOf(context, ref);

    return GlassScreen(
      particles: true,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(GlassSpacing.xl),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    GlassButton(
                      icon: Icons.arrow_back,
                      onPressed: () => Navigator.of(context).pop(),
                      variant: GlassButtonVariant.icon,
                      width: 40,
                      height: 40,
                    ),
                    const SizedBox(width: GlassSpacing.lg),
                    Text(
                      'User Settings',
                      style: GlassTypeScale.title.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: tokens.textHigh,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: GlassSpacing.xxl),

                GlassContainer(
                  padding: const EdgeInsets.all(GlassSpacing.xxl),
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
                              style: GlassTypeScale.title.copyWith(
                                color: tokens.textHigh,
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

                        const SizedBox(height: GlassSpacing.xxl),

                        Center(
                          child: Stack(
                            children: [
                              GlassContainer(
                                width: 100,
                                height: 100,
                                borderRadius: BorderRadius.circular(50),
                                child: ClipOval(
                                  child: _avatarWidget(user, tokens),
                                ),
                              ),
                              if (_isEditing)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: GlassButton(
                                    icon: Icons.camera_alt,
                                    onPressed: _uploadAvatar,
                                    variant: GlassButtonVariant.icon,
                                    width: 32,
                                    height: 32,
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: GlassSpacing.xxl),

                        _buildField(
                          'Email',
                          _emailController,
                          enabled: false,
                          icon: Icons.email,
                          tokens: tokens,
                        ),

                        const SizedBox(height: GlassSpacing.lg),

                        _buildField(
                          'Username',
                          _usernameController,
                          enabled: _isEditing,
                          icon: Icons.person,
                          tokens: tokens,
                          validator: (value) {
                            if (_isEditing &&
                                (value == null || value.trim().length < 3)) {
                              return 'Username must be at least 3 characters';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: GlassSpacing.lg),

                        _buildField(
                          'First Name',
                          _firstNameController,
                          enabled: _isEditing,
                          icon: Icons.badge,
                          tokens: tokens,
                        ),

                        const SizedBox(height: GlassSpacing.lg),

                        _buildField(
                          'Last Name',
                          _lastNameController,
                          enabled: _isEditing,
                          icon: Icons.badge,
                          tokens: tokens,
                        ),

                        if (_isEditing) ...[
                          const SizedBox(height: GlassSpacing.xl),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              GlassButton(
                                text: 'Cancel',
                                onPressed: () {
                                  setState(() {
                                    _isEditing = false;
                                    _usernameController.text =
                                        user?.username ?? '';
                                    final nameParts =
                                        (user?.fullName ?? '').trim().split(' ');
                                    _firstNameController.text =
                                        nameParts.isNotEmpty
                                            ? nameParts.first
                                            : '';
                                    _lastNameController.text =
                                        nameParts.length > 1
                                            ? nameParts.sublist(1).join(' ')
                                            : '';
                                  });
                                },
                                variant: GlassButtonVariant.outlined,
                              ),
                              const SizedBox(width: GlassSpacing.md),
                              GlassButton(
                                text: 'Save',
                                onPressed: _isSaving ? null : _saveProfile,
                                variant: GlassButtonVariant.elevated,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: GlassSpacing.xl),

                GlassContainer(
                  padding: const EdgeInsets.all(GlassSpacing.xxl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Security',
                        style: GlassTypeScale.title.copyWith(
                          color: tokens.textHigh,
                        ),
                      ),
                      const SizedBox(height: GlassSpacing.lg),
                      ScreenListRow(
                        icon: Icons.lock,
                        title: 'Change Password',
                        subtitle: 'Choose a new password for your account',
                        tokens: tokens,
                        onTap: () => _showChangePasswordDialog(tokens),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: tokens.textLow,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: GlassSpacing.xl),

                GlassContainer(
                  padding: const EdgeInsets.all(GlassSpacing.xxl),
                  gradientColors: [
                    tokens.error.withValues(alpha: 0.1),
                    tokens.warning.withValues(alpha: 0.05),
                  ],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Danger Zone',
                        style: GlassTypeScale.title.copyWith(
                          color: tokens.error,
                        ),
                      ),
                      const SizedBox(height: GlassSpacing.lg),
                      GlassButton(
                        text: 'Delete Account',
                        icon: Icons.delete_forever,
                        onPressed: () => _showDeleteAccountDialog(tokens),
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
    );
  }

  Widget _avatarWidget(User? user, GlassColorTokens tokens) {
    final avatarUrl = user?.avatarUrl;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      final url = avatarUrl.startsWith('http')
          ? avatarUrl
          : '${ApiConfig.baseUrl}$avatarUrl';
      return Image.network(
        url,
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _avatarPlaceholder(tokens),
      );
    }
    return _avatarPlaceholder(tokens);
  }

  Widget _avatarPlaceholder(GlassColorTokens tokens) {
    return Icon(
      Icons.person,
      size: 50,
      color: tokens.textMedium,
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    bool enabled = true,
    IconData? icon,
    String? Function(String?)? validator,
    required GlassColorTokens tokens,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GlassTypeScale.label.copyWith(color: tokens.textMedium),
        ),
        const SizedBox(height: GlassSpacing.sm),
        GlassTextField(
          controller: controller,
          enabled: enabled,
          prefixIcon:
              icon != null ? Icon(icon, color: tokens.textMedium) : null,
          validator: validator,
        ),
      ],
    );
  }

  Future<void> _showChangePasswordDialog(GlassColorTokens tokens) async {
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
            prefixIcon: Icon(Icons.lock, color: tokens.textMedium),
          ),
          const SizedBox(height: GlassSpacing.lg),
          GlassTextField(
            controller: newPasswordController,
            hintText: 'New Password (min 8 characters)',
            obscureText: true,
            prefixIcon: Icon(Icons.lock_outline, color: tokens.textMedium),
          ),
          const SizedBox(height: GlassSpacing.lg),
          GlassTextField(
            controller: confirmPasswordController,
            hintText: 'Confirm Password',
            obscureText: true,
            prefixIcon: Icon(Icons.lock_outline, color: tokens.textMedium),
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

    if (result ?? false) {
      final newPassword = newPasswordController.text;
      if (newPassword.length < 8) {
        if (mounted) {
          context.showErrorSnackBar(
              'New password must be at least 8 characters');
        }
      } else if (newPassword != confirmPasswordController.text) {
        if (mounted) {
          context.showErrorSnackBar('Passwords do not match');
        }
      } else {
        try {
          await ref.read(apiServiceProvider).changePassword(
                currentPassword: currentPasswordController.text,
                newPassword: newPassword,
              );
          if (mounted) {
            context.showSuccessSnackBar('Password changed successfully');
          }
        } catch (e) {
          if (mounted) {
            context.showErrorSnackBar('Failed to change password: $e');
          }
        }
      }
    }

    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
  }

  Future<void> _showDeleteAccountDialog(GlassColorTokens tokens) async {
    final passwordController = TextEditingController();

    final result = await showGlassDialog<bool>(
      context: context,
      title: const Text('Delete Account'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Are you sure you want to delete your account? This action cannot be undone.',
            style: GlassTypeScale.body.copyWith(color: tokens.textHigh),
          ),
          const SizedBox(height: GlassSpacing.lg),
          GlassTextField(
            controller: passwordController,
            hintText: 'Password',
            obscureText: true,
            prefixIcon: Icon(Icons.lock, color: tokens.textMedium),
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
          text: 'Delete Account',
          onPressed: () => Navigator.of(context).pop(true),
          variant: GlassButtonVariant.elevated,
        ),
      ],
    );

    if (result ?? false) {
      try {
        await ref
            .read(apiServiceProvider).deleteAccount(passwordController.text);
        await ref.read(authProvider.notifier).logout();
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('Failed to delete account: $e');
        }
      }
    }

    passwordController.dispose();
  }
}
