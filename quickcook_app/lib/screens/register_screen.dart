import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <--- ADDED for inputFormatters
import '../services/api_service.dart';
import '../widgets/app_message.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;

  void register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    final error = await ApiService.register(
      nameController.text.trim(),
      emailController.text.trim(),
      passwordController.text.trim(),
    );

    if (!mounted) return;
    setState(() => isLoading = false);

    if (error == null) {
      // Registration stores a token; clear it so the user signs in explicitly on Login.
      await ApiService.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(
            postRegistrationMessage:
                'Account created. Please sign in with your email and password.',
          ),
        ),
        (route) => false,
      );
    } else {
      AppMessage.show(
        context,
        text: error,
        type: AppMessageType.error,
      );
    }
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
                color: cs.primary.withOpacity(0.12),
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
                color: cs.tertiary.withOpacity(0.10),
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
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
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: cs.primary.withOpacity(0.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.person_add_rounded,
                              color: cs.onPrimary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            "Create Account",
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
                        "Join QuickCook today.",
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 28),

                      Container(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh.withOpacity(0.88),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: cs.outlineVariant),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(
                                Theme.of(context).brightness == Brightness.dark
                                    ? 0.4
                                    : 0.08,
                              ),
                              blurRadius: 26,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Your Details",
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.4,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Create your account and start cooking smarter",
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 24),

                              TextFormField(
                                controller: nameController,
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                                textCapitalization: TextCapitalization.words,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[\x20-\x7E]'),
                                  ),
                                ],
                                decoration: InputDecoration(
                                  hintText: "Full Name",
                                  filled: true,
                                  fillColor: cs.surfaceContainerLow,
                                  prefixIcon: Icon(
                                    Icons.person_outline_rounded,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) return "Name is required";
                                  if (value.length < 2) return "Minimum 2 characters";
                                  return null;
                                },
                              ),

                              const SizedBox(height: 14),

                              TextFormField(
                                controller: emailController,
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                                keyboardType: TextInputType.emailAddress,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[\x20-\x7E]'),
                                  ),
                                ],
                                decoration: InputDecoration(
                                  hintText: "Email Address",
                                  filled: true,
                                  fillColor: cs.surfaceContainerLow,
                                  prefixIcon: Icon(
                                    Icons.email_outlined,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) return "Email is required";
                                  if (!value.contains("@")) return "Please enter a valid email";
                                  return null;
                                },
                              ),

                              const SizedBox(height: 14),

                              TextFormField(
                                controller: passwordController,
                                obscureText: true,
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[\x20-\x7E]'),
                                  ),
                                ],
                                decoration: InputDecoration(
                                  hintText: "Password",
                                  filled: true,
                                  fillColor: cs.surfaceContainerLow,
                                  prefixIcon: Icon(
                                    Icons.lock_outline_rounded,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onFieldSubmitted: (_) => register(),
                                validator: (value) {
                                  if (value == null || value.isEmpty) return "Password is required";
                                  if (value.length < 6) return "Minimum 6 characters";
                                  return null;
                                },
                              ),

                              const SizedBox(height: 20),

                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    gradient: LinearGradient(
                                      colors: [cs.primary, cs.secondary],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      if (!isLoading)
                                        BoxShadow(
                                          color: cs.primary.withOpacity(0.32),
                                          blurRadius: 16,
                                          offset: const Offset(0, 8),
                                        ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: isLoading ? null : register,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      foregroundColor: cs.onPrimary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: isLoading
                                        ? SizedBox(
                                            height: 24,
                                            width: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: cs.onPrimary,
                                            ),
                                          )
                                        : Text(
                                            "Sign Up",
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                              letterSpacing: 0.4,
                                              color: cs.onPrimary,
                                            ),
                                          ),
                                  ),
                                ),
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
                            "Already have an account?",
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              foregroundColor: cs.primary,
                            ),
                            child: const Text(
                              "Log In",
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
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
