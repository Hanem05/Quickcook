import 'dart:convert';
import 'dart:typed_data'; // ADDED: For handling raw file bytes
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_saver/file_saver.dart'; // ADDED: Cross-platform file saving
import '../models/recipe.dart';
import '../services/api_service.dart';
import 'recipes_form_screen.dart';
import 'create_user_screen.dart';
import 'login_screen.dart';
import '../models/admin_stats.dart';

class AdminRecipesScreen extends StatefulWidget {
  const AdminRecipesScreen({super.key});

  @override
  State<AdminRecipesScreen> createState() => _AdminRecipesScreenState();
}

class _AdminRecipesScreenState extends State<AdminRecipesScreen> {
  // --- CORE DATA ---
  List<Recipe> recipes = [];
  List<dynamic> users = [];
  List<dynamic> popularRecipes = [];
  List<dynamic> ingredientUsage = [];
  List<dynamic> apiUsageData = [];
  List<dynamic> errorLogs = [];
  List<dynamic> performanceMetrics = [];
  List<dynamic> activityLogs = [];

  String _errorSeverity = 'all';
  final TextEditingController _errorTypeController = TextEditingController();
  final TextEditingController _errorStartController = TextEditingController();
  final TextEditingController _errorEndController = TextEditingController();
  int _errorLogsPage = 1;
  int _errorLogsLastPage = 1;
  int _errorLogsTotal = 0;
  bool _errorLogsLoading = false;
  static const int _kErrorLogsPerPage = 15;
  AdminStats? adminStats;
  Map<String, dynamic>? activityStats;
  int totalUsers = 0;
  int totalRecipes = 0;
  bool loading = true;

  int _activityPage = 1;
  bool _isLoadingMore = false;
  bool _hasMoreActivity = true;

  String? _selectedInsightDate;
  String? _selectedInsightMonth;

  int _apiDisplayCount = 5;

  // --- NAVIGATION & SEARCH STATE ---
  int _selectedIndex = 0;
  // 🌿 ADDED: Search Controllers
  final TextEditingController userSearchController = TextEditingController();
  final TextEditingController recipeSearchController = TextEditingController();

  // --- PREMIUM BRAND COLORS ---
  static const Color primaryBrand = Color(0xFF0D9488);
  static const Color primaryBrandLight = Color(0xFF2DD4BF);
  static const Color darkSlate = Color(0xFF18181B);
  static const Color bgSoft = Color(0xFFF4F4F5);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFE4E4E7);
  static const Color textMain = Color(0xFF27272A);
  static const Color textMuted = Color(0xFF71717A);
  static const Color dangerRed = Color(0xFFEF4444);
  static const Color successEmerald = Color(0xFF10B981);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color infoBlue = Color(0xFF0EA5E9);

  @override
  void initState() {
    super.initState();
    // 🌿 ADDED: UI listeners to refresh when searching
    userSearchController.addListener(() => setState(() {}));
    recipeSearchController.addListener(() => setState(() {}));

    // 🔥 AUTO SET TODAY
    final now = DateTime.now();
    _selectedInsightDate =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    loadData();
  }

  @override
  void dispose() {
    userSearchController.dispose();
    recipeSearchController.dispose();
    _errorTypeController.dispose();
    _errorStartController.dispose();
    _errorEndController.dispose();
    super.dispose();
  }

  // --- DATA SYNC ---
  /// Recipes and users load independently. `/recipes` is public; `/users` is admin-only — if users
  /// fails, we must still apply recipes or the Recipe Library stays empty after a successful fetch.
  Future<void> loadData() async {
    setState(() => loading = true);
    List<Recipe> recipeData = [];
    List<dynamic> userData = [];
    bool recipesOk = false;
    bool usersOk = false;

    try {
      recipeData = await ApiService.fetchRecipes();
      recipesOk = true;
    } catch (e) {
      debugPrint('Admin load recipes: $e');
    }
    try {
      userData = await ApiService.fetchUsers();
      usersOk = true;
    } catch (e) {
      debugPrint('Admin load users: $e');
    }

    if (!mounted) return;
    setState(() {
      recipes = recipeData;
      users = userData;
      totalRecipes = recipeData.length;
      totalUsers = userData.length;
      loading = false;
    });
    _loadAnalyticsInBackground();
    _apiDisplayCount = 5;

    if (!recipesOk && !usersOk && mounted) {
      _showSnackBar("System Sync Failed", isError: true);
    }
  }

  /// Loads each analytics endpoint on its own. A single failure no longer clears the whole dashboard.
  Future<void> _loadAnalyticsInBackground() async {
    AdminStats? nextAdminStats;
    List<dynamic>? nextPopular;
    Map<String, dynamic>? nextActivityStats;
    List<dynamic>? nextIngredientUsage;
    List<dynamic>? nextErrorLogs;
    Map<String, dynamic>? nextErrorMeta;
    List<dynamic>? nextActivityLogs;
    List<dynamic>? nextApiUsage;
    List<dynamic>? nextPerformance;

    try {
      nextAdminStats = await ApiService.fetchAdminStats();
    } catch (e) {
      debugPrint('admin stats: $e');
    }
    try {
      nextPopular = await ApiService.fetchPopularRecipes();
    } catch (e) {
      debugPrint('popular: $e');
    }
    try {
      nextActivityStats = await ApiService.fetchActivityStats();
    } catch (e) {
      debugPrint('activity stats: $e');
    }
    try {
      nextIngredientUsage = await ApiService.fetchIngredientUsage(
        date: _selectedInsightDate,
        month: _selectedInsightMonth,
      );
    } catch (e) {
      debugPrint('ingredient usage: $e');
    }
    try {
      final r = await ApiService.fetchErrorLogsPaginated(
        page: 1,
        perPage: _kErrorLogsPerPage,
      );
      nextErrorLogs = r['items'] as List<dynamic>;
      final m = r['meta'];
      if (m is Map) {
        nextErrorMeta = Map<String, dynamic>.from(m);
      }
    } catch (e) {
      debugPrint('error logs: $e');
    }
    try {
      nextActivityLogs = await ApiService.fetchActivityLogs(_activityPage);
    } catch (e) {
      debugPrint('activity logs: $e');
    }
    try {
      nextApiUsage = await ApiService.fetchApiUsage();
    } catch (e) {
      debugPrint('api usage: $e');
    }
    try {
      nextPerformance = await ApiService.fetchPerformanceMetrics();
    } catch (e) {
      debugPrint('performance metrics: $e');
    }

    if (!mounted) return;
    setState(() {
      if (nextAdminStats != null) adminStats = nextAdminStats;
      if (nextPopular != null) popularRecipes = nextPopular;
      if (nextActivityStats != null) activityStats = nextActivityStats;
      if (nextIngredientUsage != null) ingredientUsage = nextIngredientUsage;
      if (nextErrorLogs != null) errorLogs = nextErrorLogs;
      if (nextErrorMeta != null) _applyErrorLogsMeta(nextErrorMeta);
      if (nextActivityLogs != null) {
        activityLogs = nextActivityLogs;
        _hasMoreActivity = nextActivityLogs.length == 10;
      }
      if (nextApiUsage != null) apiUsageData = nextApiUsage;
      if (nextPerformance != null) performanceMetrics = nextPerformance;
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 400,
        elevation: 6,
        backgroundColor: isError ? dangerRed : darkSlate,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> loadInitial() async {
    if (_isLoadingMore || !_hasMoreActivity) return;

    setState(() => _isLoadingMore = true);

    _activityPage++;

    try {
      final newLogs = await ApiService.fetchActivityLogs(_activityPage);

      setState(() {
        activityLogs.addAll(newLogs);

        if (newLogs.length < 10) {
          _hasMoreActivity = false;
        }

        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() => _isLoadingMore = false);
    }
  }

  // --- EXPORT LOGIC ---
  Future<void> _exportToCSV(
    String filename,
    List<String> headers,
    List<List<String>> rows,
  ) async {
    String csvData = headers.join(',') + '\n';

    for (var row in rows) {
      csvData +=
          row.map((item) => '"${item.replaceAll('"', '""')}"').join(',') + '\n';
    }

    final Uint8List bytes = Uint8List.fromList(utf8.encode(csvData));

    await FileSaver.instance.saveFile(
      name: '$filename.csv',
      bytes: bytes,
      mimeType: MimeType.csv,
    );

    _showSnackBar("Successfully downloaded $filename.csv!");
  }

  // 🌿 ADDED: Dialog for New Ingredient
  void _showAddIngredientDialog() {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: surfaceWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          "Add New Ingredient",
          style: TextStyle(fontWeight: FontWeight.w900, color: textMain),
        ),
        content: _buildDialogTextField(
          label: "Ingredient Name",
          icon: Icons.kitchen_rounded,
          controller: nameController,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBrand,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              if (nameController.text.isEmpty) return;
              Navigator.pop(context);
              try {
                await ApiService.createIngredient(nameController.text.trim());
                _showSnackBar("Ingredient added successfully!");
              } catch (e) {
                _showSnackBar("Failed to add ingredient.", isError: true);
              }
            },
            child: const Text("Add to Pantry"),
          ),
        ],
      ),
    );
  }

  void _downloadUsersList() {
    final headers = ['ID', 'Name', 'Email', 'Role', 'Joined Date'];
    final rows = users
        .map(
          (u) => [
            u['id']?.toString() ?? '',
            u['name']?.toString() ?? '',
            u['email']?.toString() ?? '',
            u['role']?.toString() ?? 'user',
            u['created_at']?.toString() ?? '',
          ],
        )
        .toList();
    _exportToCSV('User_Directory', headers, rows);
  }

  void _downloadRecipesList() {
    final headers = ['ID', 'Name', 'Category', 'Rating', 'Instructions'];
    final rows = recipes
        .map(
          (r) => [
            r.id.toString(),
            r.name,
            r.category ?? 'Uncategorized',
            r.rating?.toString() ?? '0.0',
            r.instructions,
          ],
        )
        .toList();
    _exportToCSV('Recipe_Library', headers, rows);
  }

  void _downloadActivityLogs() {
    final headers = ['Date/Time', 'User', 'Action', 'Target Object'];
    final rows = activityLogs
        .map(
          (log) => [
            log['created_at']?.toString() ??
                log['timestamp']?.toString() ??
                'Unknown Date',
            log['user_name']?.toString() ?? 'System',
            log['action']?.toString() ?? 'interacted',
            (log['recipe_name'] ?? log['ingredient_name'] ?? 'System Object')
                .toString(),
          ],
        )
        .toList();
    _exportToCSV('Activity_Timeline', headers, rows);
  }

  // --- CRUD ACTIONS ---
  Future<void> deleteUser(int id) async {
    try {
      await ApiService.deleteUser(id);
      loadData();
      _showSnackBar("User removed from system.");
    } catch (e) {
      _showSnackBar("Failed to delete user.", isError: true);
    }
  }

  Future<void> _reloadIngredientInsights() async {
    try {
      final data = await ApiService.fetchIngredientUsage(
        date: _selectedInsightDate,
        month: _selectedInsightMonth,
      );

      setState(() {
        ingredientUsage = data;
      });
    } catch (e) {
      debugPrint("Insight reload error: $e");
    }
  }

  Future<void> deleteRecipe(int id) async {
    try {
      await ApiService.deleteRecipe(id);
      loadData();
      _showSnackBar("Recipe deleted successfully.");
    } catch (e) {
      _showSnackBar("Error deleting recipe.", isError: true);
    }
  }

  void showEditUserDialog(Map<String, dynamic> user) {
    TextEditingController nameController = TextEditingController(
      text: user['name'],
    );
    TextEditingController emailController = TextEditingController(
      text: user['email'],
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: surfaceWhite,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
        contentPadding: const EdgeInsets.symmetric(horizontal: 32),
        actionsPadding: const EdgeInsets.all(32),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Edit User Profile",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: textMain,
                fontSize: 24,
              ),
            ),
            SizedBox(height: 8),
            Text(
              "Update user credentials and access below.",
              style: TextStyle(
                color: textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            _buildDialogTextField(
              label: "Full Name",
              icon: Icons.person_outline,
              controller: nameController,
            ),
            const SizedBox(height: 20),
            _buildDialogTextField(
              label: "Email Address",
              icon: Icons.email_outlined,
              controller: emailController,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
            child: const Text(
              "Cancel",
              style: TextStyle(color: textMuted, fontWeight: FontWeight.w700),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBrand,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ApiService.adminUpdateUser(
                  user['id'],
                  nameController.text,
                  emailController.text,
                );
                loadData();
              } catch (e) {
                _showSnackBar("Update failed.", isError: true);
              }
            },
            child: const Text(
              "Save Changes",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogTextField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontWeight: FontWeight.w600, color: textMain),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: textMuted,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(icon, color: textMuted, size: 20),
        filled: true,
        fillColor: bgSoft,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryBrand, width: 2),
        ),
      ),
    );
  }

  // --- MAIN UI STRUCTURE ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgSoft,
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: primaryBrand,
                            strokeWidth: 4,
                          ),
                        )
                      : _buildSelectedScreen(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedScreen() {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboard();
      case 1:
        return _buildFullUsersView();
      case 2:
        return _buildFullRecipesView();
      default:
        return _buildDashboard();
    }
  }

  // --- FULL DIRECTORY VIEWS ---
  Widget _buildFullUsersView() {
    // 🌿 ADDED: Real-time filtering logic
    final filteredUsers = users.where((u) {
      final query = userSearchController.text.toLowerCase();
      final name = (u['name'] ?? '').toString().toLowerCase();
      final email = (u['email'] ?? '').toString().toLowerCase();
      return name.contains(query) || email.contains(query);
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      physics: const BouncingScrollPhysics(),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: surfaceWhite,
          borderRadius: BorderRadius.circular(24),
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: primaryBrand,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    "User Management",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: textMain,
                    ),
                  ),
                  const SizedBox(width: 32),
                  // 🌿 ADDED: Search Field
                  Expanded(
                    child: TextField(
                      controller: userSearchController,
                      decoration: InputDecoration(
                        hintText: "Search name or email...",
                        prefixIcon: const Icon(Icons.search, size: 20),
                        filled: true,
                        fillColor: bgSoft,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 32),
                  OutlinedButton.icon(
                    onPressed: _downloadUsersList,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text("Export CSV"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textMain,
                      side: const BorderSide(color: borderLight),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: borderLight),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  bgSoft.withOpacity(0.5),
                ),
                headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: textMuted,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
                dataRowMinHeight: 70,
                dataRowMaxHeight: 70,
                horizontalMargin: 32,
                dividerThickness: 1,
                columns: const [
                  DataColumn(label: Text('ID')),
                  DataColumn(label: Text('USER')),
                  DataColumn(label: Text('EMAIL')),
                  DataColumn(label: Text('ROLE')),
                  DataColumn(label: Text('JOINED DATE')),
                  DataColumn(label: Text('ACTIONS')),
                ],
                rows: filteredUsers.map((u) {
                  final role = u['role']?.toString().toLowerCase() ?? 'user';
                  final isAdmin = role == 'admin';
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          u['id']?.toString() ?? '-',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: textMuted,
                          ),
                        ),
                      ),
                      DataCell(
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: primaryBrand.withOpacity(0.1),
                              child: Text(
                                (u['name']?.toString().isNotEmpty == true)
                                    ? u['name']
                                          .toString()
                                          .substring(0, 1)
                                          .toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: primaryBrand,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              u['name'] ?? 'Unknown',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: textMain,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Text(
                          u['email'] ?? 'No email',
                          style: const TextStyle(
                            color: textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isAdmin
                                ? primaryBrand.withOpacity(0.1)
                                : infoBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            role.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: isAdmin ? primaryBrand : infoBlue,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          u['created_at']?.toString() ?? 'N/A',
                          style: const TextStyle(
                            color: textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 20,
                                color: infoBlue,
                              ),
                              tooltip: "Edit User",
                              onPressed: () => showEditUserDialog(u),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: dangerRed,
                              ),
                              tooltip: "Remove User",
                              onPressed: () => deleteUser(u['id']),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullRecipesView() {
    // 🌿 ADDED: Real-time filtering logic
    final filteredRecipes = recipes.where((r) {
      final query = recipeSearchController.text.toLowerCase();
      return r.name.toLowerCase().contains(query) ||
          (r.category?.toLowerCase() ?? "").contains(query);
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      physics: const BouncingScrollPhysics(),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: surfaceWhite,
          borderRadius: BorderRadius.circular(24),
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: primaryBrand,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    "Complete Recipe Library",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: textMain,
                    ),
                  ),
                  const SizedBox(width: 32),
                  // 🌿 ADDED: Search Field
                  Expanded(
                    child: TextField(
                      controller: recipeSearchController,
                      decoration: InputDecoration(
                        hintText: "Search dish or category...",
                        prefixIcon: const Icon(Icons.search, size: 20),
                        filled: true,
                        fillColor: bgSoft,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 32),
                  OutlinedButton.icon(
                    onPressed: _downloadRecipesList,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text("Export CSV"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textMain,
                      side: const BorderSide(color: borderLight),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: borderLight),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  bgSoft.withOpacity(0.5),
                ),
                headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: textMuted,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
                dataRowMinHeight: 76,
                dataRowMaxHeight: 76,
                horizontalMargin: 32,
                dividerThickness: 1,
                columns: const [
                  DataColumn(label: Text('ID')),
                  DataColumn(label: Text('DISH')),
                  DataColumn(label: Text('CATEGORY')),
                  DataColumn(label: Text('RATING')),
                  DataColumn(label: Text('INSTRUCTIONS SUMMARY')),
                  DataColumn(label: Text('ACTIONS')),
                ],
                rows: filteredRecipes.map((r) {
                  final categoryStr = r.category ?? 'Uncategorized';
                  final ratingsStr = r.rating?.toString() ?? 'No Rating';
                  final imageUrlStr = r.imageUrl ?? '';

                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          r.id.toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: textMuted,
                          ),
                        ),
                      ),
                      DataCell(
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: bgSoft,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: borderLight),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: imageUrlStr.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: imageUrlStr,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 96,
                                      placeholder: (context, url) => Container(
                                        color: bgSoft,
                                      ),
                                      errorWidget: (context, url, error) =>
                                          const Icon(
                                        Icons.restaurant,
                                        color: textMuted,
                                        size: 20,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.restaurant,
                                      color: textMuted,
                                      size: 20,
                                    ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 150,
                              child: Text(
                                r.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: textMain,
                                  fontSize: 14,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: bgSoft,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderLight),
                          ),
                          child: Text(
                            categoryStr,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: textMuted,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: warningAmber,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              ratingsStr,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: textMain,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 250,
                          child: Text(
                            r.instructions,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: textMuted,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 20,
                                color: infoBlue,
                              ),
                              tooltip: "Edit Recipe",
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => RecipeFormScreen(recipe: r),
                                ),
                              ).then((_) => loadData()),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: dangerRed,
                              ),
                              tooltip: "Delete Recipe",
                              onPressed: () => deleteRecipe(r.id),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- ASYMMETRICAL PRO GRID DASHBOARD ---
  Widget _buildDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatsRow(),
          const SizedBox(height: 32),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LEFT COLUMN (65% width) - Main Focus
              Expanded(
                flex: 14,
                child: Column(
                  children: [
                    _bentoBox(
                      "Search Insights",
                      "Most searched ingredients across the platform.",
                      Column(
                        children: [
                          Row(
                            children: [
                              // 📅 SELECT DATE
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: DateTime.now(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now(),
                                    );

                                    if (picked != null) {
                                      setState(() {
                                        _selectedInsightDate = picked
                                            .toIso8601String();
                                        _selectedInsightMonth = null;
                                      });

                                      await _reloadIngredientInsights();
                                    }
                                  },
                                  child: Text(
                                    _selectedInsightDate ?? "Select Date",
                                  ),
                                ),
                              ),

                              const SizedBox(width: 12),

                              // 📆 SELECT MONTH
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: DateTime.now(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now(),
                                      helpText: "Select Month",
                                    );

                                    if (picked != null) {
                                      setState(() {
                                        _selectedInsightMonth =
                                            "${picked.year}-${picked.month.toString().padLeft(2, '0')}";
                                        _selectedInsightDate = null;
                                      });

                                      await _reloadIngredientInsights();
                                    }
                                  },
                                  child: Text(
                                    _selectedInsightMonth ?? "Select Month",
                                  ),
                                ),
                              ),

                              const SizedBox(width: 12),

                              // 🔄 RESET
                              IconButton(
                                onPressed: () async {
                                  final now = DateTime.now();

                                  final today =
                                      "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

                                  setState(() {
                                    _selectedInsightDate = today; // ✅ SET TODAY
                                    _selectedInsightMonth = null;
                                  });

                                  await _reloadIngredientInsights();
                                },
                                icon: const Icon(Icons.refresh),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          _buildIngredientBarChart(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    _bentoBox(
                      "API Traffic & Latency",
                      "Real-time endpoint performance monitoring.",
                      _buildApiUsageTable(),
                    ),
                    const SizedBox(height: 32),
                    _bentoBox(
                      "System Health Status",
                      "Recent critical alerts and warnings.",
                      _buildErrorLogsSection(),
                    ),
                    const SizedBox(height: 32),
                    _bentoBox(
                      "Client performance",
                      "Screen transitions and slow API calls from the app.",
                      _buildPerformanceMetricsTable(),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 32),

              // RIGHT COLUMN (35% width) - Secondary/Feed Focus
              Expanded(
                flex: 9,
                child: Column(
                  children: [
                    _bentoBox(
                      "Category Distribution",
                      "Content spread across recipe types.",
                      _buildCategoryPieChart(),
                    ),
                    const SizedBox(height: 32),
                    _bentoBox(
                      "Trending Leaderboard",
                      "Top performing recipes right now.",
                      _buildTrendingList(),
                    ),
                    const SizedBox(height: 32),
                    _bentoBox(
                      "Activity Timeline",
                      "Live feed of user interactions.",
                      _buildActivityLogsTable(limit: 5),
                      trailingIcon: Icons.visibility,
                      onTrailingTap: _openActivityModal,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- PREMIUM BENTO BOX WRAPPER ---
  Widget _bentoBox(
    String title,
    String subtitle,
    Widget child, {
    IconData? trailingIcon,
    VoidCallback? onTrailingTap,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: surfaceWhite,
        borderRadius: BorderRadius.circular(24),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: textMain,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailingIcon != null)
                IconButton(
                  icon: Icon(trailingIcon, color: textMuted),
                  onPressed: onTrailingTap,
                  tooltip: "Download CSV",
                  style: IconButton.styleFrom(backgroundColor: bgSoft),
                ),
            ],
          ),
          const SizedBox(height: 32),
          child,
        ],
      ),
    );
  }

  // --- UPGRADED CHARTS ---
  Widget _buildCategoryPieChart() {
    if (adminStats == null || adminStats!.categoryDistribution.isEmpty) {
      return _buildEmptyState("No distribution data.", Icons.pie_chart_outline);
    }

    return SizedBox(
      height: 260,
      child: PieChart(
        PieChartData(
          sectionsSpace: 4,
          centerSpaceRadius: 60,
          sections: adminStats!.categoryDistribution.asMap().entries.map((
            entry,
          ) {
            final color = Colors.primaries[entry.key % Colors.primaries.length];
            return PieChartSectionData(
              value: entry.value.count.toDouble(),
              title: '${entry.value.count}',
              radius: 40,
              color: color.withOpacity(0.85),
              titleStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
              badgeWidget: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: surfaceWhite,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderLight),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      entry.value.category,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: textMain,
                      ),
                    ),
                  ],
                ),
              ),
              badgePositionPercentageOffset: 1.6,
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildIngredientBarChart() {
    if (ingredientUsage.isEmpty) {
      return _buildEmptyState("No search trends yet.", Icons.bar_chart_rounded);
    }
    final maxY =
        (ingredientUsage
                    .map((e) => e['count'] as int)
                    .reduce((a, b) => a > b ? a : b) +
                2)
            .toDouble();

    return SizedBox(
      height: 280,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          barGroups: ingredientUsage.asMap().entries.map((entry) {
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: (entry.value['count'] as int).toDouble(),
                  gradient: const LinearGradient(
                    colors: [primaryBrand, primaryBrandLight],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                  width: 24,
                  borderRadius: BorderRadius.circular(6),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: bgSoft,
                  ),
                ),
              ],
            );
          }).toList(),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget: (value, meta) {
                  int index = value.toInt();
                  if (index >= 0 && index < ingredientUsage.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        ingredientUsage[index]['ingredient']['name'],
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: textMuted,
                        ),
                      ),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 5,
            getDrawingHorizontalLine: (value) =>
                FlLine(color: borderLight, strokeWidth: 1, dashArray: [5, 5]),
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  // --- PRO TIMELINES & LEADERBOARDS ---
  Widget _buildTrendingList() {
    if (popularRecipes.isEmpty) {
      return _buildEmptyState(
        "No trending recipes.",
        Icons.trending_up_rounded,
      );
    }
    return Column(
      children: popularRecipes.asMap().entries.map((entry) {
        int index = entry.key;
        var item = entry.value;
        bool isTop3 = index < 3;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isTop3 ? successEmerald.withOpacity(0.04) : surfaceWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isTop3 ? successEmerald.withOpacity(0.2) : borderLight,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  "#${index + 1}",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: isTop3 ? successEmerald : borderLight,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item['recipe'] != null
                      ? item['recipe']['name']
                      : 'Unknown Recipe',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textMain,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: surfaceWhite,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderLight),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.remove_red_eye_rounded,
                      size: 14,
                      color: textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "${item['views']}",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: textMain,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // --- REFACTORED TIMELINE TILE ---
  Widget _buildTimelineTile(dynamic log, bool isLast) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: primaryBrand,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: primaryBrand.withOpacity(0.3),
                    width: 3,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: borderLight,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13, color: textMain),
                      children: [
                        TextSpan(
                          text: log['user_name'] ?? 'User ',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        TextSpan(
                          text:
                              ' ${log['action']?.toLowerCase() ?? 'interacted'}',
                          style: const TextStyle(
                            color: textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: bgSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      log['recipe_name'] ??
                          log['ingredient_name'] ??
                          "System object",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: primaryBrand,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportActivityLogsSmart({
    required List<dynamic> modalLogs,
    String? selectedDate,
    String? selectedMonth,
  }) async {
    List<dynamic> exportData = [];

    // 🔥 CASE 1: FILTERED → GET ALL DATA
    if (selectedDate != null || selectedMonth != null) {
      exportData = await ApiService.fetchAllActivityLogs(
        date: selectedDate,
        month: selectedMonth,
      );
    } else {
      // 🔥 CASE 2: NO FILTER → USE CURRENT LOADED DATA
      exportData = modalLogs;
    }

    final headers = ['Date/Time', 'User', 'Action', 'Target Object'];

    final rows = exportData.map((log) {
      return [
        log['created_at']?.toString() ?? 'Unknown',
        log['user_name']?.toString() ?? 'System',
        log['action']?.toString() ?? '',
        (log['recipe_name'] ?? log['ingredient_name'] ?? 'System').toString(),
      ];
    }).toList();

    await _exportToCSV("Activity_Logs", headers, rows);
  }

  Widget _buildActivityLogsTable({int? limit}) {
    if (activityLogs.isEmpty) {
      return _buildEmptyState("No recent activity.", Icons.history_rounded);
    }

    final displayLogs = limit != null
        ? activityLogs.take(limit).toList()
        : activityLogs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...displayLogs.asMap().entries.map((entry) {
          bool isLast = entry.key == displayLogs.length - 1;
          return _buildTimelineTile(entry.value, isLast);
        }).toList(),

        const SizedBox(height: 12),

        if (limit != null && activityLogs.length > limit)
          Center(
            child: TextButton(
              onPressed: _openActivityModal,
              child: const Text(
                "View More Activities",
                style: TextStyle(
                  color: primaryBrand,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openActivityModal() {
    int page = 1;
    List<dynamic> modalLogs = [];
    bool isLoading = true;
    bool isLoadingMore = false;
    bool hasMore = true;
    String? selectedDate;
    String? selectedMonth;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> loadInitial() async {
              final logs = await ApiService.fetchActivityLogs(
                page,
                date: selectedDate,
                month: selectedMonth,
              );

              setModalState(() {
                modalLogs = logs;
                isLoading = false;
                hasMore = logs.length == 10;
              });
            }

            Future<void> loadMore() async {
              if (isLoadingMore || !hasMore) return;

              setModalState(() => isLoadingMore = true);

              page++;

              final newLogs = await ApiService.fetchActivityLogs(
                page,
                date: selectedDate,
                month: selectedMonth,
              );

              setModalState(() {
                modalLogs.addAll(newLogs);
                isLoadingMore = false;

                if (newLogs.length < 10) {
                  hasMore = false;
                }
              });
            }

            if (isLoading) loadInitial();

            return AlertDialog(
              backgroundColor: surfaceWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "All Activity Logs",
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      _exportActivityLogsSmart(
                        modalLogs: modalLogs,
                        selectedDate: selectedDate,
                        selectedMonth: selectedMonth,
                      );
                    },
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text("Export CSV"),
                  ),
                ],
              ),
              content: SizedBox(
                width: 600,
                height: 500,
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        children: [
                          // 🔥 STEP 4 GOES HERE
                          Row(
                            children: [
                              // 📅 SELECT DATE
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: DateTime.now(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now(),
                                    );

                                    if (picked != null) {
                                      setModalState(() {
                                        selectedDate = picked.toIso8601String();
                                        selectedMonth = null;
                                        page = 1;
                                        isLoading = true;
                                      });
                                    }
                                  },
                                  child: const Text("Select Date"),
                                ),
                              ),

                              const SizedBox(width: 12),

                              // 📆 SELECT MONTH
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: DateTime.now(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now(),
                                      helpText: "Select Month",
                                      fieldHintText: "MM/YYYY",
                                    );

                                    if (picked != null) {
                                      setModalState(() {
                                        // 🔥 ONLY KEEP MONTH + YEAR
                                        selectedMonth =
                                            "${picked.year}-${picked.month.toString().padLeft(2, '0')}";

                                        selectedDate = null;
                                        page = 1;
                                        isLoading = true;
                                      });
                                    }
                                  },
                                  child: Text(selectedMonth ?? "Select Month"),
                                ),
                              ),

                              const SizedBox(width: 12),

                              // 🔄 RESET
                              IconButton(
                                onPressed: () {
                                  setModalState(() {
                                    selectedDate = null;
                                    selectedMonth = null;
                                    page = 1;
                                    isLoading = true;
                                  });
                                },
                                icon: const Icon(Icons.refresh),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // 🔥 YOUR EXISTING LIST (DO NOT TOUCH)
                          Expanded(
                            child: ListView.builder(
                              itemCount: modalLogs.length,
                              itemBuilder: (context, index) {
                                bool isLast = index == modalLogs.length - 1;
                                return _buildTimelineTile(
                                  modalLogs[index],
                                  isLast,
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 12),

                          if (hasMore)
                            ElevatedButton(
                              onPressed: isLoadingMore ? null : loadMore,
                              child: isLoadingMore
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text("Load More"),
                            )
                          else
                            const Text(
                              "No more activities",
                              style: TextStyle(color: Colors.grey),
                            ),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildApiUsageTable() {
    if (apiUsageData.isEmpty) {
      return _buildEmptyState("No API traffic recorded.", Icons.api_rounded);
    }

    // 🔥 LIMIT DATA HERE
    final displayData = apiUsageData.take(_apiDisplayCount).toList();

    return Column(
      children: [
        ...displayData.map((log) {
          final latency =
              double.tryParse(log['avg_latency']?.toString() ?? '0') ?? 0;

          final isSlow = latency > 400;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surfaceWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderLight),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: darkSlate.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    "GET",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    "/${log['endpoint']}",
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text("${log['hits']} reqs"),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSlow
                        ? dangerRed.withOpacity(0.1)
                        : successEmerald.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text("${latency.toStringAsFixed(0)} ms"),
                ),
              ],
            ),
          );
        }).toList(),

        const SizedBox(height: 10),

        // 🔥 VIEW MORE BUTTON
        if (_apiDisplayCount < apiUsageData.length)
          TextButton(
            onPressed: () {
              setState(() {
                _apiDisplayCount += 5;
              });
            },
            child: const Text(
              "View More API Traffic",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          )
        else
          const Text("No more API logs", style: TextStyle(color: Colors.grey)),
      ],
    );
  }

  void _applyErrorLogsMeta(Map<String, dynamic> m) {
    _errorLogsLastPage = (m['last_page'] as num?)?.toInt() ?? 1;
    _errorLogsTotal = (m['total'] as num?)?.toInt() ?? 0;
    final cp = (m['current_page'] as num?)?.toInt();
    if (cp != null) _errorLogsPage = cp;
  }

  Future<void> _reloadErrorLogs({bool resetPage = false}) async {
    if (resetPage) _errorLogsPage = 1;
    setState(() => _errorLogsLoading = true);
    try {
      final r = await ApiService.fetchErrorLogsPaginated(
        severity: _errorSeverity == 'all' ? null : _errorSeverity,
        errorType: _errorTypeController.text.trim().isEmpty
            ? null
            : _errorTypeController.text.trim(),
        startDate: _errorStartController.text.trim().isEmpty
            ? null
            : _errorStartController.text.trim(),
        endDate: _errorEndController.text.trim().isEmpty
            ? null
            : _errorEndController.text.trim(),
        page: _errorLogsPage,
        perPage: _kErrorLogsPerPage,
      );
      if (!mounted) return;
      setState(() {
        errorLogs = r['items'] as List<dynamic>;
        final meta = r['meta'];
        if (meta is Map) {
          _applyErrorLogsMeta(Map<String, dynamic>.from(meta));
        }
        _errorLogsLoading = false;
      });
    } catch (e) {
      debugPrint('Error log reload: $e');
      if (mounted) setState(() => _errorLogsLoading = false);
    }
  }

  Widget _buildErrorLogsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<String>(
              value: _errorSeverity,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All severities')),
                DropdownMenuItem(value: 'critical', child: Text('critical')),
                DropdownMenuItem(value: 'error', child: Text('error')),
                DropdownMenuItem(value: 'warning', child: Text('warning')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _errorSeverity = v);
              },
            ),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _errorTypeController,
                decoration: const InputDecoration(
                  hintText: 'Error type',
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _errorStartController,
                decoration: const InputDecoration(
                  hintText: 'Start YYYY-MM-DD',
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _errorEndController,
                decoration: const InputDecoration(
                  hintText: 'End YYYY-MM-DD',
                  isDense: true,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => _reloadErrorLogs(resetPage: true),
              child: const Text('Apply filters'),
            ),
          ],
        ),
        if (_errorLogsLoading) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
        const SizedBox(height: 16),
        _buildErrorLogsTable(),
      ],
    );
  }

  Widget _buildErrorLogsPagination() {
    if (_errorLogsTotal <= 0) return const SizedBox.shrink();
    final start = (_errorLogsPage - 1) * _kErrorLogsPerPage + 1;
    final end = (_errorLogsPage - 1) * _kErrorLogsPerPage + errorLogs.length;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          Text(
            '$start–$end of $_errorLogsTotal',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textMuted,
            ),
          ),
          const Spacer(),
          if (_errorLogsLastPage > 1) ...[
            IconButton(
              tooltip: 'Previous page',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: _errorLogsLoading || _errorLogsPage <= 1
                  ? null
                  : () {
                      setState(() => _errorLogsPage--);
                      _reloadErrorLogs();
                    },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Page $_errorLogsPage of $_errorLogsLastPage',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: textMain,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next page',
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: _errorLogsLoading || _errorLogsPage >= _errorLogsLastPage
                  ? null
                  : () {
                      setState(() => _errorLogsPage++);
                      _reloadErrorLogs();
                    },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPerformanceMetricsTable() {
    if (performanceMetrics.isEmpty) {
      return _buildEmptyState(
        "No performance samples yet.",
        Icons.speed_rounded,
      );
    }
    return Column(
      children: performanceMetrics.map((row) {
        final sevColor = (row['duration_ms'] as int? ?? 0) > 1500
            ? warningAmber
            : successEmerald;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: surfaceWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderLight),
          ),
          child: Row(
            children: [
              Icon(Icons.timeline, color: sevColor, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row['kind'] ?? ''} · ${row['name'] ?? ''}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${row['duration_ms'] ?? 0} ms · ${row['user_email'] ?? row['user_name'] ?? 'guest'}',
                      style: const TextStyle(fontSize: 11, color: textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildErrorLogsTable() {
    if (errorLogs.isEmpty) {
      return _buildEmptyState(
        "Systems healthy. No errors logged.",
        Icons.check_circle_outline,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...errorLogs.map(
          (error) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: dangerRed.withOpacity(0.02),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: dangerRed.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_rounded, color: dangerRed, size: 20),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: surfaceWhite,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: borderLight),
                            ),
                            child: Text(
                              (error['severity'] ?? 'error').toString(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: textMuted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (error['error_type'] != null)
                            Text(
                              error['error_type'].toString(),
                              style: const TextStyle(
                                fontSize: 11,
                                color: textMuted,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        error['message'] ?? 'Unhandled Exception',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: dangerRed,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: surfaceWhite,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: borderLight),
                        ),
                        child: Text(
                          "/${error['endpoint'] ?? 'unknown'}",
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: textMuted,
                            fontWeight: FontWeight.w600,
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
        _buildErrorLogsPagination(),
      ],
    );
  }

  // --- HEADER & SIDEBAR ---
  String get _currentHeaderTitle {
    switch (_selectedIndex) {
      case 1:
        return "User Directory";
      case 2:
        return "Recipe Library";
      default:
        return "Dashboard Overview";
    }
  }

  String get _currentHeaderSubtitle {
    switch (_selectedIndex) {
      case 1:
        return "Manage accounts, roles, and permissions.";
      case 2:
        return "Browse, edit, and moderate published recipes.";
      default:
        return "Real-time analytics and platform monitoring.";
    }
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      decoration: const BoxDecoration(
        color: surfaceWhite,
        border: Border(bottom: BorderSide(color: borderLight)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currentHeaderTitle,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: textMain,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _currentHeaderSubtitle,
                style: const TextStyle(
                  color: textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: surfaceWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderLight),
            ),
            child: IconButton(
              onPressed: () {
                loadData();
                _showSnackBar("Dashboard updated.");
              },
              icon: const Icon(Icons.sync_rounded, color: textMuted, size: 20),
              tooltip: "Refresh Data",
            ),
          ),
          // 🌿 ADDED: Add Ingredient Button
          ElevatedButton.icon(
            onPressed: _showAddIngredientDialog,
            icon: const Icon(Icons.set_meal_rounded, size: 18),
            label: const Text(
              "Add Ingredient",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: surfaceWhite,
              foregroundColor: textMain,
              elevation: 0,
              side: const BorderSide(color: borderLight),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateUserScreen()),
            ).then((_) => loadData()),
            icon: const Icon(Icons.person_add_rounded, size: 18),
            label: const Text(
              "New User",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: surfaceWhite,
              foregroundColor: textMain,
              elevation: 0,
              side: const BorderSide(color: borderLight),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecipeFormScreen()),
            ).then((_) => loadData()),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text(
              "Add Recipe",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBrand,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _statCard(
          "Total Users",
          totalUsers,
          Icons.people_alt_rounded,
          primaryBrand,
        ),
        _statCard(
          "Published Recipes",
          totalRecipes,
          Icons.menu_book_rounded,
          warningAmber,
        ),
        _statCard(
          "Total Views",
          activityStats?['views'] ?? 0,
          Icons.visibility_rounded,
          successEmerald,
        ),
        _statCard(
          "Total Favorites",
          activityStats?['favorites'] ?? 0,
          Icons.favorite_rounded,
          dangerRed,
        ),
      ],
    );
  }

  Widget _statCard(String title, dynamic value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 24),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: surfaceWhite,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 24),
            Text(
              value.toString(),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: textMain,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                color: textMuted,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      color: darkSlate,
      child: Column(
        children: [
          const SizedBox(height: 48),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surfaceWhite.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: const CircleAvatar(
              backgroundColor: primaryBrand,
              radius: 26,
              child: Icon(
                Icons.rocket_launch_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "CORE ADMIN",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: successEmerald.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              "System Online",
              style: TextStyle(
                color: successEmerald,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 48),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _navItem(
                  Icons.grid_view_rounded,
                  "Insights",
                  _selectedIndex == 0,
                  () => setState(() => _selectedIndex = 0),
                ),
                _navItem(
                  Icons.group_rounded,
                  "User Directory",
                  _selectedIndex == 1,
                  () => setState(() => _selectedIndex = 1),
                ),
                _navItem(
                  Icons.restaurant_menu_rounded,
                  "Recipe Library",
                  _selectedIndex == 2,
                  () => setState(() => _selectedIndex = 2),
                ),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(20),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              hoverColor: dangerRed.withOpacity(0.1),
              onTap: () async {
                await ApiService.logout();
                if (!mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              leading: const Icon(
                Icons.power_settings_new_rounded,
                color: dangerRed,
              ),
              title: const Text(
                "Sign Out",
                style: TextStyle(color: dangerRed, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(
    IconData icon,
    String label,
    bool active,
    VoidCallback onTap,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: active ? primaryBrand.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? primaryBrand.withOpacity(0.2) : Colors.transparent,
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(
          icon,
          color: active ? primaryBrandLight : Colors.white54,
          size: 22,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white54,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            fontSize: 14,
          ),
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(icon, size: 48, color: borderLight),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                color: textMuted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
