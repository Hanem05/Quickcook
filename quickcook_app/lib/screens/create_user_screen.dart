import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <--- ADDED for inputFormatters
import '../services/api_service.dart';

class CreateUserScreen extends StatefulWidget {
  const CreateUserScreen({super.key});

  @override
  State<CreateUserScreen> createState() => _CreateUserScreenState();
}

class _CreateUserScreenState extends State<CreateUserScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  String selectedRole = 'user';
  bool isLoading = false;

  static const Color primaryBrand = Color(0xFF0D9488);
  static const Color darkSlate = Color(0xFF18181B);
  static const Color bgSoft = Color(0xFFF4F4F5);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFE4E4E7);
  static const Color textMain = Color(0xFF27272A);
  static const Color textMuted = Color(0xFF71717A);

  Future<void> handleCreateUser() async {
    if (nameController.text.isEmpty ||
        emailController.text.isEmpty ||
        passwordController.text.isEmpty) {
      _showSnackBar("Please fill all fields", isError: true);
      return;
    }

    setState(() => isLoading = true);

    try {
      await ApiService.createUser(
        name: nameController.text,
        email: emailController.text,
        password: passwordController.text,
        role: selectedRole,
      );

      if (!mounted) return;

      _showSnackBar("Account created successfully!");
      nameController.clear();
      emailController.clear();
      passwordController.clear();
      setState(() => selectedRole = 'user');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Failed to create user.", isError: true);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 400,
        backgroundColor: isError ? Colors.redAccent : darkSlate,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgSoft,
      appBar: AppBar(
        backgroundColor: surfaceWhite,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          "User Management / New Account",
          style: TextStyle(
            color: textMain,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: borderLight, height: 1),
        ),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: surfaceWhite,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderLight),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: primaryBrand.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.person_add_alt_1_rounded, color: primaryBrand),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Create Account",
                              style: TextStyle(
                                color: textMain,
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              "Set credentials and access role for a new user.",
                              style: TextStyle(
                                color: textMuted,
                                fontWeight: FontWeight.w500,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: surfaceWhite,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderLight),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 20,
                            decoration: BoxDecoration(
                              color: primaryBrand,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Text("Account Credentials",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: textMain,
                              )),
                        ],
                      ),
                      const SizedBox(height: 22),

                      _buildTextField(
                        controller: nameController,
                        label: "Full Name",
                        icon: Icons.person_outline_rounded,
                      ),
                      const SizedBox(height: 16),

                      _buildTextField(
                        controller: emailController,
                        label: "Email Address",
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),

                      _buildTextField(
                        controller: passwordController,
                        label: "Initial Password",
                        icon: Icons.lock_outline_rounded,
                        obscureText: true,
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        "System Role",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: textMuted,
                        ),
                      ),
                      const SizedBox(height: 12),

                      DropdownButtonFormField<String>(
                        value: selectedRole,
                        dropdownColor: surfaceWhite,
                        style: const TextStyle(
                          color: textMain,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        decoration: _inputDecoration(
                          Icons.shield_outlined,
                          "Select Role",
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'user',
                            child: Text("User Access"),
                          ),
                          DropdownMenuItem(
                            value: 'admin',
                            child: Text("Admin Access"),
                          ),
                        ],
                        onChanged: (val) => setState(() => selectedRole = val!),
                      ),

                      const SizedBox(height: 30),

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : handleCreateUser,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryBrand,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  "Create New Account",
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: textMuted,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          // 🌿 BLOCKS EMOJIS - Only allows standard keyboard characters
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\x20-\x7E]')),
          ],
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: textMain,
            fontSize: 14,
          ),
          decoration: _inputDecoration(icon, "Enter $label"),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(IconData icon, String hint) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: textMuted, size: 20),
      filled: true,
      fillColor: bgSoft,
      hintText: hint,
      hintStyle: const TextStyle(
        color: textMuted,
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryBrand, width: 1.5),
      ),
    );
  }
}
