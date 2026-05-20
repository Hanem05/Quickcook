import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../navigation/app_page_route.dart';
import '../services/api_host_config.dart';
import '../services/api_service.dart';
import '../widgets/app_message.dart';
import '../widgets/modern_ui.dart';
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
  final serverHostController = TextEditingController();
  bool _showServerField = false;

  @override
  void initState() {
    super.initState();
    _initServerField();
    final msg = widget.postRegistrationMessage?.trim();
    if (msg != null && msg.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppMessage.show(context, text: msg, type: AppMessageType.success);
      });
    }
  }

  Future<void> _initServerField() async {
    final saved = await ApiHostConfig.loadSavedHost();
    if (!mounted) return;
    setState(() {
      if (saved != null && saved.isNotEmpty) {
        serverHostController.text = saved;
      }
      _showServerField = !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          (ApiHostConfig.requiresManualHost || kDebugMode);
    });
  }

  Future<void> login() async {
    if (!_formKey.currentState!.validate()) return;

    final host = serverHostController.text.trim();
    if (host.isNotEmpty) {
      await ApiHostConfig.saveHost(host);
    } else if (ApiHostConfig.requiresManualHost) {
      AppMessage.show(
        context,
        text: 'Enter your computer\'s Wi‑Fi IP (same network as this phone).',
        type: AppMessageType.error,
      );
      return;
    }

    unawaited(ApiService.fetchIngredients());
    unawaited(ApiService.fetchRecipes());

    final result = await ApiService.login(
      emailController.text,
      passwordController.text,
    );

    if (!mounted) return;

    if (result["success"] == true) {
      final data = result["data"];
      final role =
          data["role"] ?? (data["user"] != null ? data["user"]["role"] : null);

      if (role != "admin") {
        unawaited(ApiService.fetchRecommendedRecipes());
        unawaited(ApiService.fetchFavoriteIds());
        unawaited(ApiService.fetchFavorite());
        unawaited(ApiService.getCollections());
      }
      unawaited(ApiService.getUserProfile());

      if (role == "admin") {
        unawaited(ApiService.fetchRecipes());
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
    } else {
      AppMessage.show(
        context,
        text: (result["message"]?.toString().trim().isNotEmpty ?? false)
            ? result["message"].toString()
            : "Login failed. Please try again.",
        type: AppMessageType.error,
      );
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    serverHostController.dispose();
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
                            "QuickCook",
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
                        "Cook smarter. Live better.",
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
                                "Welcome Back",
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Sign in to your smart kitchen",
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                controller: emailController,
                                keyboardType: TextInputType.emailAddress,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[\x20-\x7E]'),
                                  ),
                                ],
                                decoration: const InputDecoration(
                                  hintText: "Email Address",
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return "Email is required";
                                  }
                                  if (!value.contains("@")) {
                                    return "Please enter a valid email";
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: passwordController,
                                obscureText: true,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[\x20-\x7E]'),
                                  ),
                                ],
                                decoration: const InputDecoration(
                                  hintText: "Password",
                                  prefixIcon: Icon(Icons.lock_outline_rounded),
                                ),
                                onFieldSubmitted: (_) => login(),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return "Password is required";
                                  }
                                  if (value.length < 6) {
                                    return "Minimum 6 characters";
                                  }
                                  return null;
                                },
                              ),
                              if (_showServerField) ...[
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: serverHostController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    hintText: "Server host (PC IP on Wi‑Fi)",
                                    helperText:
                                        "Emulator: leave blank. Phone: e.g. 192.168.1.10",
                                    helperMaxLines: 2,
                                    prefixIcon: Icon(
                                      Icons.dns_outlined,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ] else if (!kIsWeb &&
                                  defaultTargetPlatform == TargetPlatform.android) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () =>
                                        setState(() => _showServerField = true),
                                    icon: const Icon(Icons.settings_ethernet_rounded, size: 18),
                                    label: const Text("Set server host"),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
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
                                label: "Sign In",
                                icon: Icons.arrow_forward_rounded,
                                onPressed: login,
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
                              "Sign Up",
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
