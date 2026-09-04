import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/auth_provider.dart';
import '../../components/glass_button.dart';
import '../../components/glass_text_field.dart';
import '../../tokens/glass_tokens.dart';
import '../glass_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isPasswordVisible = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _errorMessage = null);

    final authNotifier = ref.read(authProvider.notifier);

    try {
      if (_isLogin) {
        await authNotifier.login(
          emailOrUsername: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await authNotifier.register(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          username: _usernameController.text.trim(),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final tokens = screenTokensOf(context, ref);

    return GlassScreen(
      particles: true,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(GlassSpacing.xl),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Omi RSS Reader',
                    style: GlassTypeScale.display.copyWith(
                      color: tokens.textHigh,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: GlassSpacing.sm),

                  Text(
                    _isLogin ? 'Welcome back' : 'Create an account',
                    style: GlassTypeScale.body.copyWith(
                      color: tokens.textMedium,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 48),

                  GlassTextField(
                    controller: _emailController,
                    hintText: _isLogin ? 'Email or username' : 'Email',
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: Icon(
                      Icons.email_outlined,
                      color: tokens.textMedium,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return _isLogin
                            ? 'Please enter your email or username'
                            : 'Please enter your email';
                      }
                      if (!_isLogin && !value.contains('@')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),

                  if (!_isLogin) ...[
                    const SizedBox(height: GlassSpacing.lg),

                    GlassTextField(
                      controller: _usernameController,
                      hintText: 'Username',
                      prefixIcon: Icon(
                        Icons.person_outline,
                        color: tokens.textMedium,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().length < 3) {
                          return 'Username must be at least 3 characters';
                        }
                        return null;
                      },
                    ),
                  ],

                  const SizedBox(height: GlassSpacing.lg),

                  GlassTextField(
                    controller: _passwordController,
                    hintText: 'Password',
                    obscureText: !_isPasswordVisible,
                    prefixIcon: Icon(
                      Icons.lock_outline,
                      color: tokens.textMedium,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: tokens.textMedium,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPasswordVisible = !_isPasswordVisible;
                        });
                      },
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      if (!_isLogin && value.length < 8) {
                        return 'Password must be at least 8 characters';
                      }
                      return null;
                    },
                  ),

                  if (_isLogin) ...[
                    const SizedBox(height: GlassSpacing.lg),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          // TODO: Navigate to forgot password
                        },
                        child: Text(
                          'Forgot password?',
                          style: GlassTypeScale.label.copyWith(
                            color: tokens.textMedium,
                          ),
                        ),
                      ),
                    ),
                  ],

                  if (_errorMessage != null) ...[
                    const SizedBox(height: GlassSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(GlassSpacing.md),
                      decoration: BoxDecoration(
                        color: tokens.error.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(GlassRadii.md),
                        border: Border.all(
                          color: tokens.error.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: tokens.error,
                            size: 20,
                          ),
                          const SizedBox(width: GlassSpacing.sm),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: GlassTypeScale.label.copyWith(
                                color: tokens.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: GlassSpacing.xl),

                  SizedBox(
                    width: double.infinity,
                    child: GlassButton(
                      onPressed: authState.isLoading ? null : _submit,
                      child: authState.isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: tokens.textHigh,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              _isLogin ? 'Sign In' : 'Sign Up',
                              style: GlassTypeScale.body.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: GlassSpacing.xl),

                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isLogin
                              ? "Don't have an account?"
                              : "Already have an account?",
                          style: GlassTypeScale.label.copyWith(
                            color: tokens.textMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isLogin = !_isLogin;
                              _errorMessage = null;
                            });
                          },
                          child: Text(
                            _isLogin ? 'Sign Up' : 'Sign In',
                            style: GlassTypeScale.label.copyWith(
                              color: tokens.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),

                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 1,
                          color: tokens.glassStroke,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: GlassSpacing.lg),
                        child: Text(
                          'OR',
                          style: GlassTypeScale.caption
                              .copyWith(color: tokens.textLow),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1,
                          color: tokens.glassStroke,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: GlassSpacing.xl),

                  TextButton(
                    onPressed: () {
                      ref.read(localModeProvider.notifier).enable();
                    },
                    child: Text(
                      'Continue without account',
                      style: GlassTypeScale.label.copyWith(
                        color: tokens.textMedium,
                        decoration: TextDecoration.underline,
                        decorationColor: tokens.textLow,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
