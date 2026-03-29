import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/theme_notifier.dart';
import 'login_screen.dart'; // Ensure this import is correct
// import 'collections_screen.dart'; // Uncomment this once you create the file
import 'collections_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    loadUserProfile();
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> loadUserProfile() async {
    try {
      final userData = await ApiService.getUserProfile();
      if (!mounted) return;
      setState(() {
        nameController.text = userData['name'] ?? '';
        emailController.text = userData['email'] ?? '';
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showSnackBar("Failed to load profile", isError: true);
    }
  }

  Future<void> updateProfile() async {
    setState(() => isSaving = true);
    try {
      await ApiService.updateUserProfile(
        nameController.text.trim(),
        emailController.text.trim(),
        passwordController.text.isNotEmpty ? passwordController.text : null,
      );

      if (!mounted) return;
      _showSnackBar("Profile updated successfully!", isError: false);
      passwordController.clear();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Error updating profile.", isError: true);
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  void handleLogout() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showSnackBar(String message, {required bool isError}) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 400,
        backgroundColor: isError ? Colors.redAccent : cs.inverseSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          message,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: cs.onInverseSurface,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: cs.onSurface),
        centerTitle: false,
        title: Text(
          "Profile Settings",
          style: TextStyle(
            color: cs.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: -0.5,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: cs.outlineVariant, height: 1),
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 40.0,
                    ),
                    child: Column(
                      children: [
                        _buildProfileAvatar(),
                        const SizedBox(height: 48),

                        // --- ACCOUNT INFO CARD ---
                        _buildInfoCard(),

                        const SizedBox(height: 24),

                        // --- ACTIVITY & SESSION CARD ---
                        _buildActivityCard(),

                        const SizedBox(height: 40),

                        // --- SAVE BUTTON ---
                        _buildSaveButton(),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildProfileAvatar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 120,
      width: 120,
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.12),
        shape: BoxShape.circle,
        border: Border.all(color: cs.outlineVariant, width: 4),
      ),
      child: Center(
        child: Container(
          height: 90,
          width: 90,
          decoration: BoxDecoration(
            color: cs.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: cs.primary.withOpacity(0.35),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.person_rounded,
            size: 48,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader("Account Information"),
          const SizedBox(height: 32),
          _buildTextField(
            label: "Display Name",
            icon: Icons.person_outline_rounded,
            controller: nameController,
          ),
          const SizedBox(height: 24),
          _buildTextField(
            label: "Email Address",
            icon: Icons.email_outlined,
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 24),
          _buildTextField(
            label: "Change Password",
            hint: "Leave blank to keep current",
            icon: Icons.lock_outline_rounded,
            controller: passwordController,
            obscureText: true,
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 8,
            ),
            leading: Icon(
              Icons.folder_special_rounded,
              color: cs.primary,
            ),
            title: Text(
              "My Collections",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            subtitle: Text(
              "Manage your saved recipe folders",
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CollectionsScreen()),
              );
            },
          ),
          Divider(height: 1, color: cs.outlineVariant, indent: 24, endIndent: 24),
          Consumer<ThemeNotifier>(
            builder: (context, tn, _) {
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                leading: Icon(Icons.palette_outlined, color: cs.primary),
                title: Text(
                  'Theme',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                subtitle: Text(
                  'Light, dark, or match the system',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                trailing: DropdownButton<ThemeMode>(
                  value: tn.mode,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  dropdownColor: cs.surfaceContainerHigh,
                  iconEnabledColor: cs.onSurface,
                  items: [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('System', style: TextStyle(color: cs.onSurface)),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text('Light', style: TextStyle(color: cs.onSurface)),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text('Dark', style: TextStyle(color: cs.onSurface)),
                    ),
                  ],
                  onChanged: (m) {
                    if (m != null) tn.setMode(m);
                  },
                ),
              );
            },
          ),
          Divider(height: 1, color: cs.outlineVariant, indent: 24, endIndent: 24),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 8,
            ),
            leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            title: const Text(
              "Sign Out",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.redAccent,
              ),
            ),
            subtitle: Text(
              "Exit your current session",
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            onTap: handleLogout,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: isSaving ? null : updateProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: isSaving
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: cs.onPrimary,
                ),
              )
            : const Text(
                "Save Changes",
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    String? hint,
    required IconData icon,
    required TextEditingController controller,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
            fontSize: 14,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\x20-\x7E]')),
          ],
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: cs.onSurfaceVariant, size: 20),
            filled: true,
            fillColor: cs.surfaceContainerLow,
            hintText: hint,
            hintStyle: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
