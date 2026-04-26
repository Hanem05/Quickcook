import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/app_message.dart';
import 'login_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _token = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _token.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final err = await ApiService.resetPassword(
      email: _email.text.trim(),
      token: _token.text.trim(),
      password: _password.text,
      passwordConfirmation: _password2.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (err == null) {
      AppMessage.show(
        context,
        text: 'Password updated. Please sign in.',
        type: AppMessageType.success,
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } else {
      AppMessage.show(
        context,
        text: err,
        type: AppMessageType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Reset password'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
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
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh.withOpacity(0.88),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: cs.outlineVariant),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(
                          Theme.of(context).brightness == Brightness.dark ? 0.4 : 0.08,
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
                          "Set New Password",
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Use the token from email to secure your account.",
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined, color: cs.onSurfaceVariant),
                            filled: true,
                            fillColor: cs.surfaceContainerLow,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _token,
                          decoration: InputDecoration(
                            hintText: 'Token (from email)',
                            prefixIcon: Icon(Icons.key_rounded, color: cs.onSurfaceVariant),
                            filled: true,
                            fillColor: cs.surfaceContainerLow,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: 'New password',
                            prefixIcon: Icon(Icons.lock_outline_rounded, color: cs.onSurfaceVariant),
                            filled: true,
                            fillColor: cs.surfaceContainerLow,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (v) => v == null || v.length < 8 ? 'Min 8 characters' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password2,
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: 'Confirm password',
                            prefixIcon: Icon(Icons.verified_user_outlined, color: cs.onSurfaceVariant),
                            filled: true,
                            fillColor: cs.surfaceContainerLow,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (v) => v != _password.text ? 'Must match' : null,
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                colors: [cs.primary, cs.secondary],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: ElevatedButton(
                              onPressed: _loading ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                              ),
                              child: _loading
                                  ? SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: cs.onPrimary,
                                      ),
                                    )
                                  : Text(
                                      'Update password',
                                      style: TextStyle(
                                        color: cs.onPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
