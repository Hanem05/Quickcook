import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/theme_notifier.dart';
import '../widgets/app_message.dart';
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

  bool _hasFetched = false;
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
    // Never blank the page — the layout is mostly static. Just fill in the
    // fields when data arrives.
    try {
      final userData = await ApiService.getUserProfile();
      if (!mounted) return;
      setState(() {
        if (nameController.text != (userData['name'] ?? '')) {
          nameController.text = userData['name'] ?? '';
        }
        if (emailController.text != (userData['email'] ?? '')) {
          emailController.text = userData['email'] ?? '';
        }
        _hasFetched = true;
      });
    } catch (e) {
      if (!mounted) return;
      // Only complain if there really is no data to show.
      if (nameController.text.isEmpty) {
        _showSnackBar("Failed to load profile", isError: true);
      }
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
    AppMessage.show(
      context,
      text: message,
      type: isError ? AppMessageType.error : AppMessageType.success,
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
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 24.0,
              ),
              child: Column(
                children: [
                  _buildProfileHero(),
                  const SizedBox(height: 16),
                  _buildInfoCard(),
                  const SizedBox(height: 16),
                  _buildActivityCard(),
                  const SizedBox(height: 24),
                  _buildSaveButton(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHero() {
    final cs = Theme.of(context).colorScheme;
    final userName = nameController.text.trim().isEmpty
        ? "QuickCook User"
        : nameController.text.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.035,
            ),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildProfileAvatar(),
          const SizedBox(height: 12),
          Text(
            "Account",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            userName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 24,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            emailController.text.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileAvatar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 76,
      width: 76,
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.10),
        shape: BoxShape.circle,
        border: Border.all(color: cs.outlineVariant, width: 2),
      ),
      child: Center(
        child: Container(
          height: 58,
          width: 58,
          decoration: BoxDecoration(
            color: cs.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: cs.primary.withOpacity(0.28),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            Icons.person_rounded,
            size: 30,
            color: cs.onPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.035,
            ),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader("Account Information"),
          const SizedBox(height: 20),
          _buildTextField(
            label: "Display Name",
            icon: Icons.person_outline_rounded,
            controller: nameController,
          ),
          const SizedBox(height: 14),
          _buildTextField(
            label: "Email Address",
            icon: Icons.email_outlined,
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
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
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.035,
            ),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
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
                  horizontal: 16,
                  vertical: 6,
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
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
              horizontal: 16,
              vertical: 6,
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
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
            fontSize: 16,
            fontWeight: FontWeight.w800,
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
      height: 54,
      child: ElevatedButton.icon(
        onPressed: isSaving ? null : updateProfile,
        icon: isSaving
            ? SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: cs.onPrimary,
                ),
              )
            : Icon(Icons.save_outlined, color: cs.onPrimary, size: 18),
        label: Text(
          isSaving ? "Saving..." : "Save Changes",
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: cs.onPrimary,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          disabledBackgroundColor: cs.surfaceContainerHighest,
          disabledForegroundColor: cs.onSurfaceVariant,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
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
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: TextStyle(
            fontWeight: FontWeight.w600,
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
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.primary, width: 1.3),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }
}
