import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../navigation/app_page_route.dart';
import '../services/api_service.dart';
import '../widgets/app_message.dart';
import '../widgets/modern_ui.dart';
import '../utils/varchar_limits.dart';
import '../widgets/terms_acceptance_row.dart';
import 'main_landing_shell_screen.dart';
import 'register_screen.dart';
import 'admin_recipes_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.postRegistrationMessage});

  final String? postRegistrationMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool _acceptedTerms = false;
  bool _loggingIn = false;

  @override
  void initState() {
    super.initState();
    final msg = widget.postRegistrationMessage?.trim();
    if (msg != null && msg.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppMessage.show(context, text: msg, type: AppMessageType.success);
      });
    }
  }

  String? _roleFromLoginData(Map<String, dynamic> data) {
    final role = data['role'];
    if (role != null) return role.toString();
    final user = data['user'];
    if (user is Map && user['role'] != null) {
      return user['role'].toString();
    }
    return null;
  }

  Future<void> login() async {
    if (!_formKey.currentState!.validate()) return;
    if (_loggingIn) return;

    setState(() => _loggingIn = true);

    unawaited(ApiService.fetchIngredients());
    unawaited(ApiService.fetchRecipesBrowsePage(page: 1, perPage: 10));

    final result = await ApiService.login(
      emailController.text.trim(),
      passwordController.text,
    );

    if (!mounted) {
      return;
    }

    setState(() => _loggingIn = false);

    if (result['success'] != true) {
      AppMessage.show(
        context,
        text: (result['message']?.toString().trim().isNotEmpty ?? false)
            ? result['message'].toString()
            : 'Login failed. Please try again.',
        type: AppMessageType.error,
      );
      return;
    }

    final data = Map<String, dynamic>.from(result['data'] as Map);
    final role = _roleFromLoginData(data);
    final isAdmin = role == 'admin';

    if (!isAdmin && !_acceptedTerms) {
      await ApiService.logout();
      if (!mounted) return;
      AppMessage.show(
        context,
        text: 'Please accept the Terms & Regulations to sign in.',
        type: AppMessageType.error,
      );
      return;
    }

    if (!isAdmin) {
      unawaited(ApiService.fetchRecommendedRecipes());
      unawaited(ApiService.fetchFavoriteIds());
      unawaited(ApiService.fetchFavorite());
      unawaited(ApiService.getCollections());
    }
    unawaited(ApiService.getUserProfile());

    if (isAdmin) {
      unawaited(ApiService.fetchRecipesBrowsePage(page: 1, perPage: 10));
      Navigator.pushReplacement(
        context,
        AppPageRoute.smooth(const AdminRecipesScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        AppPageRoute.smooth(const MainLandingShellScreen()),
      );
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -90,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.tertiary.withValues(alpha: 0.10),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            height: 54,
                            width: 54,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [cs.primary, cs.secondary],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: cs.primary.withValues(alpha: 0.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.restaurant_menu_rounded,
                              color: cs.onPrimary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'QuickCook',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.6,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Cook smarter. Live better.',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 28),
                      ModernSurface(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome Back',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Sign in to your smart kitchen',
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                controller: emailController,
                                keyboardType: TextInputType.emailAddress,
                                maxLength: kDbVarchar255,
                                inputFormatters: varchar255AsciiFormatters(),
                                decoration: const InputDecoration(
                                  hintText: 'Email Address',
                                  prefixIcon: Icon(Icons.email_outlined),
                                  counterText: '',
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Email is required';
                                  }
                                  if (!value.contains('@')) {
                                    return 'Please enter a valid email';
                                  }
                                  return validateVarchar255(
                                    value,
                                    fieldLabel: 'Email',
                                  );
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: passwordController,
                                obscureText: true,
                                maxLength: kDbVarchar255,
                                inputFormatters: varchar255AsciiFormatters(),
                                decoration: const InputDecoration(
                                  hintText: 'Password',
                                  prefixIcon: Icon(Icons.lock_outline_rounded),
                                  counterText: '',
                                ),
                                onFieldSubmitted: (_) => login(),
                                validator: validatePassword255,
                              ),
                              const SizedBox(height: 8),
                              TermsAcceptanceRow(
                                value: _acceptedTerms,
                                onChanged: (v) =>
                                    setState(() => _acceptedTerms = v == true),
                                onViewTerms: () =>
                                    TermsAcceptanceRow.showTermsDialog(context),
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      AppPageRoute.smooth(
                                        const ForgotPasswordScreen(),
                                      ),
                                    );
                                  },
                                  child: const Text(
                                    'Forgot password?',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              ModernPrimaryButton(
                                label: 'Sign In',
                                icon: Icons.arrow_forward_rounded,
                                busy: _loggingIn,
                                busyLabel: 'Signing in…',
                                onPressed: _loggingIn ? null : login,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Don't have an account?",
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              AppPageRoute.smooth(const RegisterScreen()),
                            ),
                            child: const Text(
                              'Sign Up',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
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
}
