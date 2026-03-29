import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <--- ADDED for inputFormatters
import '../services/api_service.dart';
import 'home_screen.dart';

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
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } else {
      // 🚨 SHOW EXACT ERROR MESSAGE FROM BACKEND
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error, // <--- This will show the exact Laravel validation error
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(20),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- MODERN TEAL & ZINC PALETTE ---
    const Color primaryBrand = Color(0xFF0D9488);
    const Color bgSoft = Color(0xFFF4F4F5);
    const Color surfaceWhite = Color(0xFFFFFFFF);
    const Color textMain = Color(0xFF27272A);
    const Color textMuted = Color(0xFF71717A);

    return Scaffold(
      backgroundColor: bgSoft,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              // 🌿 WEB RESPONSIVENESS (Prevents stretching)
              constraints: const BoxConstraints(maxWidth: 450),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 90,
                    width: 90,
                    decoration: BoxDecoration(
                      color: primaryBrand.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Center(
                      child: Container(
                        height: 60,
                        width: 60,
                        decoration: BoxDecoration(
                          color: primaryBrand,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: primaryBrand.withOpacity(0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.person_add_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text(
                    "Create Account",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: textMain,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Join QuickCook today.",
                    style: TextStyle(
                      color: textMuted,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 40),

                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: surfaceWhite,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 24,
                          spreadRadius: 0,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Your Details",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: textMain,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // FULL NAME INPUT
                          TextFormField(
                            controller: nameController,
                            style: const TextStyle(
                              color: textMain,
                              fontWeight: FontWeight.w600,
                            ),
                            textCapitalization: TextCapitalization.words,
                            // 🌿 BLOCKS EMOJIS
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[\x20-\x7E]'),
                              ),
                            ],
                            decoration: InputDecoration(
                              labelText: "Full Name",
                              labelStyle: const TextStyle(
                                color: textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                              filled: true,
                              fillColor: bgSoft,
                              prefixIcon: const Icon(
                                Icons.person_outline_rounded,
                                color: textMuted,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: primaryBrand,
                                  width: 2,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty)
                                return "Name is required";
                              if (value.length < 2)
                                return "Minimum 2 characters";
                              return null;
                            },
                          ),

                          const SizedBox(height: 20),

                          // EMAIL INPUT
                          TextFormField(
                            controller: emailController,
                            style: const TextStyle(
                              color: textMain,
                              fontWeight: FontWeight.w600,
                            ),
                            keyboardType: TextInputType.emailAddress,
                            // 🌿 BLOCKS EMOJIS
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[\x20-\x7E]'),
                              ),
                            ],
                            decoration: InputDecoration(
                              labelText: "Email Address",
                              labelStyle: const TextStyle(
                                color: textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                              filled: true,
                              fillColor: bgSoft,
                              prefixIcon: const Icon(
                                Icons.email_outlined,
                                color: textMuted,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: primaryBrand,
                                  width: 2,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty)
                                return "Email is required";
                              if (!value.contains("@"))
                                return "Please enter a valid email";
                              return null;
                            },
                          ),

                          const SizedBox(height: 20),

                          // PASSWORD INPUT
                          TextFormField(
                            controller: passwordController,
                            obscureText: true,
                            style: const TextStyle(
                              color: textMain,
                              fontWeight: FontWeight.w600,
                            ),
                            // 🌿 BLOCKS EMOJIS
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[\x20-\x7E]'),
                              ),
                            ],
                            decoration: InputDecoration(
                              labelText: "Password",
                              labelStyle: const TextStyle(
                                color: textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                              filled: true,
                              fillColor: bgSoft,
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                color: textMuted,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: primaryBrand,
                                  width: 2,
                                ),
                              ),
                            ),
                            onFieldSubmitted: (_) => register(),
                            validator: (value) {
                              if (value == null || value.isEmpty)
                                return "Password is required";
                              if (value.length < 6)
                                return "Minimum 6 characters";
                              return null;
                            },
                          ),

                          const SizedBox(height: 32),

                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: isLoading ? null : register,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryBrand,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      "Sign Up",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Already have an account?",
                        style: TextStyle(
                          color: textMuted,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: primaryBrand,
                        ),
                        child: const Text(
                          "Log In",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
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
    );
  }
}
