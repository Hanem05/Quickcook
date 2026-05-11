import 'dart:async';
import 'dart:convert';
import 'dart:typed_data'; // ADDED: For handling raw file bytes
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_saver/file_saver.dart'; // ADDED: Cross-platform file saving
import 'package:provider/provider.dart';
import '../models/recipe.dart';
import '../services/api_service.dart';
import '../theme/theme_notifier.dart';
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
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
  static const int _kErrorLogsPerPage = 10;
  AdminStats? adminStats;
  Map<String, dynamic>? activityStats;
  int totalUsers = 0;
  int totalRecipes = 0;
  bool loading = false;
  bool _hasFetched = false;

  int _activityPage = 1;
  bool _isLoadingMore = false;
  bool _hasMoreActivity = true;

  String? _selectedInsightDate;
  String? _selectedInsightMonth;

  int _apiUsagePage = 1;
  int _apiUsageLastPage = 1;
  int _apiUsageTotal = 0;
  bool _apiUsageLoading = false;
  bool _apiUsageLoadingMore = false;
  static const int _kApiUsagePerPage = 10;

  int _performancePage = 1;
  int _performanceLastPage = 1;
  int _performanceTotal = 0;
  bool _performanceLoading = false;
  bool _performanceLoadingMore = false;
  static const int _kPerformancePerPage = 10;

  static const int _usersRowsPerPage = 20;
  static const int _recipesRowsPerPage = 20;
  int _usersPage = 0;
  int _recipesPage = 0;

  // --- NAVIGATION & SEARCH STATE ---
  // Start admins directly in the full recipe library for faster moderation.
  int _selectedIndex = 2;
  // 🌿 ADDED: Search Controllers
  final TextEditingController userSearchController = TextEditingController();
  final TextEditingController recipeSearchController = TextEditingController();
  int _userSearchMode = 0; // 0=all, 1=first name, 2=surname

  // --- PREMIUM BRAND COLORS ---
  static const Color primaryBrand = Color(0xFFC2410C);
  static const Color primaryBrandLight = Color(0xFFFBBF24);
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

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _pageBg => _isDark ? const Color(0xFF0F0F12) : bgSoft;
  Color get _panelBg => _isDark ? const Color(0xFF1A1A1E) : surfaceWhite;
  Color get _panelBorder => _isDark ? const Color(0xFF2F2F36) : borderLight;
  Color get _mainText => _isDark ? const Color(0xFFE4E4E7) : textMain;
  Color get _mutedText => _isDark ? const Color(0xFFB0B0BA) : textMuted;
  Color get _sidebarBg => _isDark ? const Color(0xFF0B0B0E) : darkSlate;
  Color get _sidebarText => _isDark ? const Color(0xFFE4E4E7) : Colors.white;
  Color get _sidebarSurface =>
      _isDark ? const Color(0xFF151923) : const Color(0xFF252836);
  Color get _sidebarBorder =>
      _isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.12);
  Color get _sidebarMuted =>
      _isDark ? Colors.white.withValues(alpha: 0.56) : Colors.white.withValues(alpha: 0.66);
  Color get _panelShadowColor =>
      _isDark ? Colors.black.withOpacity(0.35) : Colors.black.withOpacity(0.03);
  Color get _brandSoft => primaryBrand.withValues(alpha: _isDark ? 0.20 : 0.10);
  Color get _brandStroke =>
      primaryBrand.withValues(alpha: _isDark ? 0.36 : 0.26);

  @override
  void initState() {
    super.initState();
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
  /// Stale-while-revalidate: dashboard renders cached data IMMEDIATELY and
  /// only shows the full-screen spinner when there is genuinely nothing on
  /// screen yet. Recipes/users still load independently so a failure on one
  /// does not blank the other.
  Future<void> loadData() async {
    final hasAnythingOnScreen = recipes.isNotEmpty || users.isNotEmpty;
    if (!hasAnythingOnScreen && !_hasFetched) {
      setState(() => loading = true);
    }

    List<Recipe> recipeData = recipes;
    List<dynamic> userData = users;
    bool recipesOk = false;
    bool usersOk = false;

    final recipesFuture = ApiService.fetchRecipes();
    final usersFuture = ApiService.fetchUsers();
    try {
      recipeData = await recipesFuture;
      recipesOk = true;
    } catch (e) {
      debugPrint('Admin load recipes: $e');
    }
    try {
      userData = await usersFuture;
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
      _hasFetched = true;
    });
    _loadAnalyticsInBackground();

    // Only complain if we have NOTHING usable on screen.
    if (!recipesOk && !usersOk && recipes.isEmpty && users.isEmpty && mounted) {
      _showSnackBar("System Sync Failed", isError: true);
    }
  }

  Future<void> _refreshCoreDataInBackground({
    bool includeAnalytics = false,
    bool showToast = false,
  }) async {
    try {
      final results = await Future.wait<dynamic>([
        ApiService.fetchRecipes(forceRefresh: true),
        ApiService.fetchUsers(forceRefresh: true),
      ]);
      if (!mounted) return;
      final recipeData = (results[0] as List<Recipe>);
      final userData = (results[1] as List<dynamic>);
      setState(() {
        recipes = recipeData;
        users = userData;
        totalRecipes = recipeData.length;
        totalUsers = userData.length;
      });
      if (includeAnalytics) {
        unawaited(_loadAnalyticsInBackground());
      }
      if (showToast && mounted) {
        _showSnackBar("Dashboard updated.");
      }
    } catch (e) {
      debugPrint('background refresh: $e');
      if (showToast && mounted) {
        _showSnackBar("Refresh failed.", isError: true);
      }
    }
  }

  /// Loads each analytics endpoint on its own. A single failure no longer clears the whole dashboard.
  Future<void> _loadAnalyticsInBackground() async {
    AdminStats? nextAdminStats;
    List<dynamic>? nextPopular;
    Map<String, dynamic>? nextActivityStats;
    List<dynamic>? nextIngredientUsage;
    List<dynamic>? nextActivityLogs;

    await Future.wait<void>([
      () async {
        try {
          nextAdminStats = await ApiService.fetchAdminStats();
        } catch (e) {
          debugPrint('admin stats: $e');
        }
      }(),
      () async {
        try {
          nextPopular = await ApiService.fetchPopularRecipes();
        } catch (e) {
          debugPrint('popular: $e');
        }
      }(),
      () async {
        try {
          nextActivityStats = await ApiService.fetchActivityStats();
        } catch (e) {
          debugPrint('activity stats: $e');
        }
      }(),
      () async {
        try {
          nextIngredientUsage = await ApiService.fetchIngredientUsage(
            date: _selectedInsightDate,
            month: _selectedInsightMonth,
          );
        } catch (e) {
          debugPrint('ingredient usage: $e');
        }
      }(),
      () async {
        try {
          nextActivityLogs = await ApiService.fetchActivityLogs(_activityPage);
        } catch (e) {
          debugPrint('activity logs: $e');
        }
      }(),
    ]);

    if (!mounted) return;
    setState(() {
      if (nextAdminStats != null) adminStats = nextAdminStats;
      if (nextPopular != null) popularRecipes = nextPopular!;
      if (nextActivityStats != null) activityStats = nextActivityStats!;
      if (nextIngredientUsage != null) ingredientUsage = nextIngredientUsage!;
      if (nextActivityLogs != null) {
        activityLogs = nextActivityLogs!;
        _hasMoreActivity = nextActivityLogs!.length == 10;
      }
    });

    unawaited(_reloadApiUsage(reset: true));
    unawaited(_reloadErrorLogs(resetPage: true));
    unawaited(_reloadPerformanceMetrics(reset: true));
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
        backgroundColor: _panelBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: primaryBrand.withOpacity(0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.kitchen_rounded, color: primaryBrand, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Add New Ingredient",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _mainText,
                  fontSize: 22,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Create a pantry ingredient that can be reused in recipes.",
                style: TextStyle(
                  color: _mutedText,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
              _buildDialogTextField(
                label: "Ingredient Name",
                icon: Icons.kitchen_rounded,
                controller: nameController,
              ),
            ],
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _panelBorder),
                    foregroundColor: _mainText,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  child: const Text("Cancel"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBrand,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) {
                      _showSnackBar("Ingredient name is required.", isError: true);
                      return;
                    }
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
              ),
            ],
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
    final backup = List<dynamic>.from(users);
    setState(() {
      users.removeWhere((u) => (u['id'] as int?) == id);
      totalUsers = users.length;
    });
    try {
      await ApiService.deleteUser(id);
      _showSnackBar("User removed from system.");
    } catch (e) {
      if (mounted) {
        setState(() {
          users = backup;
          totalUsers = users.length;
        });
      }
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
    final backup = List<Recipe>.from(recipes);
    setState(() {
      recipes.removeWhere((r) => r.id == id);
      totalRecipes = recipes.length;
    });
    try {
      await ApiService.deleteRecipe(id);
      _showSnackBar("Recipe deleted successfully.");
    } catch (e) {
      if (mounted) {
        setState(() {
          recipes = backup;
          totalRecipes = recipes.length;
        });
      }
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
        backgroundColor: _panelBg,
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
      style: TextStyle(fontWeight: FontWeight.w600, color: _mainText),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: _mutedText,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(icon, color: _mutedText, size: 20),
        filled: true,
        fillColor: _pageBg,
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
    final isCompactLayout = MediaQuery.of(context).size.width < 1180;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _pageBg,
      drawer: isCompactLayout
          ? Drawer(
              width: 300,
              backgroundColor: Colors.transparent,
              child: SafeArea(
                child: _buildSidebar(),
              ),
            )
          : null,
      body: isCompactLayout
          ? Column(
              children: [
                _buildHeader(
                  isCompactLayout: true,
                  onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                Expanded(
                  child: loading && !_hasFetched
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: primaryBrand,
                            strokeWidth: 4,
                          ),
                        )
                      : _buildSelectedScreen(),
                ),
              ],
            )
          : Row(
              children: [
                _buildSidebar(),
                Expanded(
                  child: Column(
                    children: [
                      _buildHeader(),
                      Expanded(
                        child: loading && !_hasFetched
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
      case 3:
        return _buildOperationsMonitorView();
      default:
        return _buildDashboard();
    }
  }

  String _readUserFirstName(Map<String, dynamic> user) {
    final direct = (user['first_name'] ?? user['firstname'] ?? '')
        .toString()
        .trim();
    if (direct.isNotEmpty) return direct.toLowerCase();

    final full = (user['name'] ?? '').toString().trim();
    if (full.isEmpty) return '';
    return full.split(RegExp(r'\s+')).first.toLowerCase();
  }

  String _readUserLastName(Map<String, dynamic> user) {
    final direct = (user['last_name'] ?? user['lastname'] ?? '')
        .toString()
        .trim();
    if (direct.isNotEmpty) return direct.toLowerCase();

    final full = (user['name'] ?? '').toString().trim();
    if (full.isEmpty) return '';
    final parts = full.split(RegExp(r'\s+'));
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  bool _matchesUserSearch(Map<String, dynamic> user, String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return true;

    final name = (user['name'] ?? '').toString().toLowerCase();
    final email = (user['email'] ?? '').toString().toLowerCase();
    final firstName = _readUserFirstName(user);
    final lastName = _readUserLastName(user);

    String normalizeValue(String value) =>
        value.replaceFirst(RegExp(r'^(first|firstname|last|lastname|surname)\s*:?\s*'), '').trim();

    if (query.startsWith('first:') || query.startsWith('firstname:')) {
      final value = normalizeValue(query);
      return value.isNotEmpty && firstName.contains(value);
    }
    if (query.startsWith('last:') ||
        query.startsWith('lastname:') ||
        query.startsWith('surname:')) {
      final value = normalizeValue(query);
      return value.isNotEmpty && lastName.contains(value);
    }
    if (query.startsWith('first ') || query.startsWith('firstname ')) {
      final value = normalizeValue(query);
      return value.isNotEmpty && firstName.contains(value);
    }
    if (query.startsWith('last ') ||
        query.startsWith('lastname ') ||
        query.startsWith('surname ')) {
      final value = normalizeValue(query);
      return value.isNotEmpty && lastName.contains(value);
    }

    if (_userSearchMode == 1) return firstName.contains(query);
    if (_userSearchMode == 2) return lastName.contains(query);

    return name.contains(query) || email.contains(query);
  }

  // --- FULL DIRECTORY VIEWS ---
  Widget _buildFullUsersView() {
    // Filter first, then paginate to avoid rendering huge tables on each tab switch.
    final filteredUsers = users.where((u) {
      return _matchesUserSearch(
        u,
        userSearchController.text,
      );
    }).toList();
    final userTotalPages =
        ((filteredUsers.length + _usersRowsPerPage - 1) ~/ _usersRowsPerPage)
            .clamp(1, 999999);
    final safeUsersPage = _usersPage >= userTotalPages
        ? userTotalPages - 1
        : _usersPage;
    final userStart = safeUsersPage * _usersRowsPerPage;
    final userEnd = (userStart + _usersRowsPerPage > filteredUsers.length)
        ? filteredUsers.length
        : userStart + _usersRowsPerPage;
    final visibleUsers = filteredUsers.sublist(userStart, userEnd);
    final screenW = MediaQuery.sizeOf(context).width;
    final userNameMaxWidth = screenW < 900 ? 160.0 : 220.0;

    final panelOuterPad = screenW < 900 ? 16.0 : 40.0;
    final headerInnerPad = screenW < 900 ? 20.0 : 32.0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(panelOuterPad),
      physics: const BouncingScrollPhysics(),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: _panelBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _panelBorder),
          boxShadow: [
            BoxShadow(
              color: _panelShadowColor,
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.all(headerInnerPad),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrowHeader = constraints.maxWidth < 720;
                  final titleStyle = TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _mainText,
                  );
                  final accentBar = Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: primaryBrand,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                  final searchBlock = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: userSearchController,
                        onChanged: (_) => setState(() => _usersPage = 0),
                        decoration: InputDecoration(
                          hintText: "Search users...",
                          prefixIcon: const Icon(Icons.search, size: 20),
                          filled: true,
                          fillColor: _pageBg,
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
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text("All"),
                            selected: _userSearchMode == 0,
                            onSelected: (_) {
                              setState(() {
                                _userSearchMode = 0;
                                _usersPage = 0;
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text("First Name"),
                            selected: _userSearchMode == 1,
                            onSelected: (_) {
                              setState(() {
                                _userSearchMode = 1;
                                _usersPage = 0;
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text("Surname"),
                            selected: _userSearchMode == 2,
                            onSelected: (_) {
                              setState(() {
                                _userSearchMode = 2;
                                _usersPage = 0;
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  );
                  final exportBtn = OutlinedButton.icon(
                    onPressed: _downloadUsersList,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text("Export CSV"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _mainText,
                      side: BorderSide(color: _panelBorder),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );

                  if (narrowHeader) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            accentBar,
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "User Management",
                                style: titleStyle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        searchBlock,
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: exportBtn,
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      accentBar,
                      const SizedBox(width: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          "User Management",
                          style: titleStyle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: searchBlock),
                      const SizedBox(width: 16),
                      exportBtn,
                    ],
                  );
                },
              ),
            ),
            Divider(height: 1, color: _panelBorder),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  _isDark ? _pageBg : bgSoft.withOpacity(0.5),
                ),
                headingTextStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _mutedText,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
                dataTextStyle: TextStyle(
                  color: _mainText,
                  fontWeight: FontWeight.w600,
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
                rows: visibleUsers.map((u) {
                  final role = u['role']?.toString().toLowerCase() ?? 'user';
                  final isAdmin = role == 'admin';
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          u['id']?.toString() ?? '-',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _mutedText,
                          ),
                        ),
                      ),
                      DataCell(
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: userNameMaxWidth + 52),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                    primaryBrand.withValues(alpha: 0.1),
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
                              Expanded(
                                child: Text(
                                  u['name'] ?? 'Unknown',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: _mainText,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Text(
                            u['email'] ?? 'No email',
                            style: TextStyle(
                              color: _mutedText,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
                          style: TextStyle(
                            color: _mutedText,
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
                }).toList(growable: false),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: _buildStandardPaginationBar(
                summary: filteredUsers.isEmpty
                    ? "No users"
                    : "Showing ${userStart + 1}-$userEnd of ${filteredUsers.length}",
                pageLabel: "${safeUsersPage + 1}/$userTotalPages",
                currentPage: safeUsersPage + 1,
                totalPages: userTotalPages,
                onJumpToPage: (page) => setState(() => _usersPage = page - 1),
                canGoPrev: safeUsersPage > 0,
                canGoNext: safeUsersPage < userTotalPages - 1,
                onPrev: () => setState(() => _usersPage = safeUsersPage - 1),
                onNext: () => setState(() => _usersPage = safeUsersPage + 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStandardPaginationBar({
    required String summary,
    required String pageLabel,
    int? currentPage,
    int? totalPages,
    ValueChanged<int>? onJumpToPage,
    bool canGoPrev = false,
    bool canGoNext = false,
    VoidCallback? onPrev,
    VoidCallback? onNext,
    String? actionLabel,
    VoidCallback? onAction,
    bool actionLoading = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _pageBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _panelBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              summary,
              style: TextStyle(
                color: _mutedText,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            ElevatedButton(
              onPressed: actionLoading ? null : onAction,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: primaryBrand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: actionLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      actionLabel,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
            ),
            const SizedBox(width: 10),
          ],
          if (onJumpToPage != null &&
              currentPage != null &&
              ((totalPages == null) || totalPages > 1)) ...[
            OutlinedButton.icon(
              onPressed: () =>
                  _showPageJumpDialog(currentPage, totalPages, onJumpToPage),
              icon: const Icon(Icons.swap_horiz_rounded, size: 16),
              label: const Text("Jump"),
              style: OutlinedButton.styleFrom(
                foregroundColor: _mainText,
                side: BorderSide(color: _panelBorder),
                backgroundColor: _panelBg,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          _pagerIcon(
            icon: Icons.chevron_left_rounded,
            enabled: canGoPrev,
            onTap: onPrev,
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _panelBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _panelBorder),
            ),
            child: Text(
              pageLabel,
              style: TextStyle(
                color: _mainText,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          _pagerIcon(
            icon: Icons.chevron_right_rounded,
            enabled: canGoNext,
            onTap: onNext,
          ),
        ],
      ),
    );
  }

  Widget _buildModalLoadMoreButton({
    required bool isLoading,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.expand_more_rounded, size: 18),
      label: Text(
        isLoading ? "Loading..." : "Load More",
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: primaryBrand,
        foregroundColor: Colors.white,
        disabledBackgroundColor: primaryBrand.withValues(alpha: 0.55),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size(140, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _buildModalEndText(String text) {
    return Text(
      text,
      style: TextStyle(
        color: _mutedText,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    );
  }

  Widget _buildDialogSecondaryButton({
    required VoidCallback onPressed,
    String label = "Close",
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _mainText,
        side: BorderSide(color: _panelBorder),
        backgroundColor: _panelBg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildDialogPrimaryButton({
    required VoidCallback onPressed,
    required String label,
    IconData? icon,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.auto_awesome_rounded, size: 16),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: primaryBrand,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _showPageJumpDialog(
    int currentPage,
    int? totalPages,
    ValueChanged<int> onJumpToPage,
  ) async {
    final controller = TextEditingController(text: currentPage.toString());
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) {
        final hint = totalPages == null
            ? "Enter a page number (1+)"
            : "Enter a page number (1-$totalPages)";
        return AlertDialog(
          backgroundColor: _panelBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            "Jump to page",
            style: TextStyle(color: _mainText, fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hint,
                style: TextStyle(color: _mutedText, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: "Page",
                  filled: true,
                  fillColor: _pageBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _panelBorder),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("Cancel", style: TextStyle(color: _mutedText)),
            ),
            ElevatedButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed == null || parsed < 1) {
                  return;
                }
                if (totalPages != null && parsed > totalPages) {
                  return;
                }
                Navigator.pop(ctx, parsed);
              },
              child: const Text("Go"),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (selected == null) return;
    onJumpToPage(selected);
  }

  Widget _pagerIcon({
    required IconData icon,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: enabled ? _panelBg : _pageBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _panelBorder),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? _mainText : _mutedText,
        ),
      ),
    );
  }

  Widget _buildFullRecipesView() {
    // Filter first, then paginate so recipe cards/images don't all build at once.
    final filteredRecipes = recipes.where((r) {
      final query = recipeSearchController.text.toLowerCase();
      return r.name.toLowerCase().contains(query) ||
          (r.category?.toLowerCase() ?? "").contains(query);
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final recipeTotalPages =
        ((filteredRecipes.length + _recipesRowsPerPage - 1) ~/
                _recipesRowsPerPage)
            .clamp(1, 999999);
    final safeRecipesPage = _recipesPage >= recipeTotalPages
        ? recipeTotalPages - 1
        : _recipesPage;
    final recipeStart = safeRecipesPage * _recipesRowsPerPage;
    final recipeEnd =
        (recipeStart + _recipesRowsPerPage > filteredRecipes.length)
        ? filteredRecipes.length
        : recipeStart + _recipesRowsPerPage;
    final visibleRecipes = filteredRecipes.sublist(recipeStart, recipeEnd);
    final screenW = MediaQuery.sizeOf(context).width;
    final dishNameMaxWidth = screenW < 900 ? 200.0 : 240.0;
    final instructionsColWidth = screenW < 1000 ? 160.0 : 250.0;

    final panelOuterPad = screenW < 900 ? 16.0 : 40.0;
    final headerInnerPad = screenW < 900 ? 20.0 : 32.0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(panelOuterPad),
      physics: const BouncingScrollPhysics(),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: _panelBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _panelBorder),
          boxShadow: [
            BoxShadow(
              color: _panelShadowColor,
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.all(headerInnerPad),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrowHeader = constraints.maxWidth < 720;
                  final titleStyle = TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _mainText,
                  );
                  final accentBar = Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: primaryBrand,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                  final searchField = TextField(
                    controller: recipeSearchController,
                    onChanged: (_) => setState(() => _recipesPage = 0),
                    decoration: InputDecoration(
                      hintText: "Search dish or category...",
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: _pageBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0,
                        horizontal: 16,
                      ),
                    ),
                  );
                  final exportBtn = OutlinedButton.icon(
                    onPressed: _downloadRecipesList,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text("Export CSV"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _mainText,
                      side: BorderSide(color: _panelBorder),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );

                  if (narrowHeader) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            accentBar,
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Complete Recipe Library",
                                style: titleStyle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        searchField,
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: exportBtn,
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      accentBar,
                      const SizedBox(width: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Text(
                          "Complete Recipe Library",
                          style: titleStyle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: searchField),
                      const SizedBox(width: 16),
                      exportBtn,
                    ],
                  );
                },
              ),
            ),
            Divider(height: 1, color: _panelBorder),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  _isDark ? _pageBg : bgSoft.withOpacity(0.5),
                ),
                headingTextStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _mutedText,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
                dataTextStyle: TextStyle(
                  color: _mainText,
                  fontWeight: FontWeight.w600,
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
                rows: visibleRecipes.map((r) {
                  final categoryStr = r.category ?? 'Uncategorized';
                  final ratingsStr = r.rating?.toString() ?? 'No Rating';
                  final imageUrlStr = r.imageUrl ?? '';

                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          r.id.toString(),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _mutedText,
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
                                color: _pageBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _panelBorder),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: imageUrlStr.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: imageUrlStr,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 96,
                                      placeholder: (context, url) => Container(
                                        color: _pageBg,
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Icon(
                                        Icons.restaurant,
                                        color: _mutedText,
                                        size: 20,
                                      ),
                                    )
                                  : Icon(
                                      Icons.restaurant,
                                      color: _mutedText,
                                      size: 20,
                                    ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: dishNameMaxWidth,
                              child: Text(
                                r.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _mainText,
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
                            color: _pageBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _panelBorder),
                          ),
                          child: Text(
                            categoryStr,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _mutedText,
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
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _mainText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: instructionsColWidth,
                          child: Text(
                            r.instructions,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _mutedText,
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
                }).toList(growable: false),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: _buildStandardPaginationBar(
                summary: filteredRecipes.isEmpty
                    ? "No recipes"
                    : "Showing ${recipeStart + 1}-$recipeEnd of ${filteredRecipes.length}",
                pageLabel: "${safeRecipesPage + 1}/$recipeTotalPages",
                currentPage: safeRecipesPage + 1,
                totalPages: recipeTotalPages,
                onJumpToPage: (page) => setState(() => _recipesPage = page - 1),
                canGoPrev: safeRecipesPage > 0,
                canGoNext: safeRecipesPage < recipeTotalPages - 1,
                onPrev: () => setState(() => _recipesPage = safeRecipesPage - 1),
                onNext: () => setState(() => _recipesPage = safeRecipesPage + 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- ASYMMETRICAL PRO GRID DASHBOARD ---
  Widget _buildDashboard() {
    final isCompactLayout = MediaQuery.of(context).size.width < 1300;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isCompactLayout ? 20 : 40),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInsightsHero(),
          const SizedBox(height: 22),
          _buildStatsRow(),
          const SizedBox(height: 32),

          if (isCompactLayout)
            Column(
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
                const SizedBox(height: 24),
                _bentoBox(
                      "Category Distribution",
                      "Content spread across recipe types.",
                      _buildCategoryPieChart(),
                ),
                const SizedBox(height: 24),
                _bentoBox(
                      "Trending Leaderboard",
                      "Top performing recipes right now.",
                      _buildTrendingList(),
                ),
                const SizedBox(height: 24),
                _bentoBox(
                      "Operations Monitoring",
                      "API traffic, activity timeline, system health, and client performance moved to a dedicated page.",
                      _buildOperationsShortcut(),
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                                          _selectedInsightDate = picked.toIso8601String();
                                          _selectedInsightMonth = null;
                                        });
                                        await _reloadIngredientInsights();
                                      }
                                    },
                                    child: Text(_selectedInsightDate ?? "Select Date"),
                                  ),
                                ),
                                const SizedBox(width: 12),
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
                                    child: Text(_selectedInsightMonth ?? "Select Month"),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                IconButton(
                                  onPressed: () async {
                                    final now = DateTime.now();
                                    final today =
                                        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
                                    setState(() {
                                      _selectedInsightDate = today;
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
                        "Operations Monitoring",
                        "API traffic, activity timeline, system health, and client performance moved to a dedicated page.",
                        _buildOperationsShortcut(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 32),
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
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildOperationsShortcut() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryBrand.withValues(alpha: _isDark ? 0.22 : 0.10),
            _panelBg,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _brandStroke),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: _isDark ? 0.10 : 0.75),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _panelBorder),
            ),
            child: const Icon(Icons.monitor_heart_rounded, size: 20, color: primaryBrand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Open Dedicated Operations Console",
                  style: TextStyle(
                    color: _mainText,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  "View API traffic, timeline, system health, and client performance in one place.",
                  style: TextStyle(
                    color: _mutedText,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.2,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => setState(() => _selectedIndex = 3),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text("Open"),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBrand,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryBrand.withValues(alpha: _isDark ? 0.30 : 0.14),
            primaryBrandLight.withValues(alpha: _isDark ? 0.22 : 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _brandStroke),
        boxShadow: [
          BoxShadow(
            color: primaryBrand.withValues(alpha: _isDark ? 0.25 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: _isDark ? 0.10 : 0.72),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.insights_rounded, color: primaryBrand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Insights Command Deck",
                  style: TextStyle(
                    color: _mainText,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Executive overview for growth, engagement, and recipe performance.",
                  style: TextStyle(
                    color: _mutedText,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
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
        color: _panelBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _panelBorder, width: 1.1),
        boxShadow: [
          BoxShadow(
            color: _panelShadowColor,
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: _pageBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _panelBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _brandSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _brandStroke),
                  ),
                  child: Icon(Icons.dashboard_customize_rounded, size: 18, color: primaryBrand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: _mainText,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: _mutedText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailingIcon != null && onTrailingTap != null)
                  OutlinedButton.icon(
                    onPressed: onTrailingTap,
                    icon: Icon(trailingIcon, color: _mainText, size: 17),
                    label: const Text("Open Full View"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _mainText,
                      side: BorderSide(color: _panelBorder),
                      backgroundColor: _panelBg,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
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
    int _readCount(dynamic row) {
      if (row is! Map) return 0;
      final raw = row['count'];
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }

    String _readIngredientName(dynamic row) {
      if (row is! Map) return 'Unknown';
      final ingredientRaw = row['ingredient'];
      if (ingredientRaw is Map) {
        final ingredient = Map<String, dynamic>.from(ingredientRaw);
        final rawName = ingredient['name'];
        if (rawName != null) {
          final name = rawName.toString().trim();
          if (name.isNotEmpty) return name;
        }
      }
      final fallback = row['ingredient_name']?.toString().trim() ?? '';
      return fallback.isNotEmpty ? fallback : 'Unknown';
    }

    final maxY =
        (ingredientUsage
                    .map((e) => _readCount(e))
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
                  toY: _readCount(entry.value).toDouble(),
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
                        _readIngredientName(ingredientUsage[index]),
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
    final topViews = popularRecipes
        .map((e) => int.tryParse(e['views']?.toString() ?? '0') ?? 0)
        .fold<int>(1, (a, b) => a > b ? a : b);
    return Column(
      children: popularRecipes.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        final rank = index + 1;
        final views = int.tryParse(item['views']?.toString() ?? '0') ?? 0;
        final ratio = (views / topViews).clamp(0.0, 1.0);
        final isTop3 = index < 3;
        final rankColor = switch (rank) {
          1 => const Color(0xFFF59E0B),
          2 => const Color(0xFF94A3B8),
          3 => const Color(0xFFB45309),
          _ => _mutedText
        };
        final recipeName = item['recipe'] != null
            ? item['recipe']['name']?.toString() ?? 'Unknown Recipe'
            : 'Unknown Recipe';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: _panelBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isTop3
                  ? primaryBrand.withValues(alpha: _isDark ? 0.36 : 0.22)
                  : _panelBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: isTop3
                    ? primaryBrand.withValues(alpha: _isDark ? 0.20 : 0.09)
                    : Colors.black.withValues(alpha: _isDark ? 0.12 : 0.03),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: rankColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '#$rank',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: rankColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      recipeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _mainText,
                        fontSize: 14.2,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _pageBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _panelBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.remove_red_eye_rounded,
                          size: 14,
                          color: _mutedText,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$views',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: _mainText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor: _pageBg,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isTop3 ? primaryBrand : _mutedText.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(growable: false),
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
        if (limit == null) ...[
          const SizedBox(height: 10),
          _buildStandardPaginationBar(
            summary: "Loaded ${activityLogs.length} activity rows",
            pageLabel: "$_activityPage/${_hasMoreActivity ? '?' : _activityPage}",
            currentPage: _activityPage,
            totalPages: null,
            onJumpToPage: (page) => unawaited(_goToActivityPage(page)),
            canGoPrev: _activityPage > 1,
            canGoNext: _hasMoreActivity,
            onPrev: () => unawaited(_goToActivityPage(_activityPage - 1)),
            onNext: () => unawaited(_goToActivityPage(_activityPage + 1)),
          ),
        ],
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

            String _fmtDate(String iso) {
              final parsed = DateTime.tryParse(iso);
              if (parsed == null) return iso;
              return "${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}";
            }

            return AlertDialog(
              backgroundColor: _panelBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              title: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: _pageBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _panelBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: primaryBrand.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.timeline_rounded,
                        color: primaryBrand,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "All Activity Logs",
                            style: TextStyle(
                              color: _mainText,
                              fontWeight: FontWeight.w900,
                              fontSize: 19,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Track user activity in real-time",
                            style: TextStyle(
                              color: _mutedText,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        _exportActivityLogsSmart(
                          modalLogs: modalLogs,
                          selectedDate: selectedDate,
                          selectedMonth: selectedMonth,
                        );
                      },
                      icon: const Icon(Icons.download_rounded, size: 17),
                      label: const Text("Export CSV"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _mainText,
                        side: BorderSide(color: _panelBorder),
                        backgroundColor: _panelBg,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: 600,
                height: 500,
                child: isLoading
                    ? Center(child: CircularProgressIndicator(color: _mainText))
                    : Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _pageBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _panelBorder),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.now(),
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime.now(),
                                      );
                                      if (picked != null) {
                                        setModalState(() {
                                          selectedDate = _fmtDate(picked.toIso8601String());
                                          selectedMonth = null;
                                          page = 1;
                                          isLoading = true;
                                        });
                                      }
                                    },
                                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                                    label: Text(selectedDate == null ? "Select Date" : _fmtDate(selectedDate!)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _mainText,
                                      side: BorderSide(color: _panelBorder),
                                      backgroundColor: _panelBg,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
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
                                          selectedMonth =
                                              "${picked.year}-${picked.month.toString().padLeft(2, '0')}";
                                          selectedDate = null;
                                          page = 1;
                                          isLoading = true;
                                        });
                                      }
                                    },
                                    icon: const Icon(Icons.date_range_rounded, size: 18),
                                    label: Text(selectedMonth ?? "Select Month"),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _mainText,
                                      side: BorderSide(color: _panelBorder),
                                      backgroundColor: _panelBg,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton.filledTonal(
                                  onPressed: () {
                                    setModalState(() {
                                      selectedDate = null;
                                      selectedMonth = null;
                                      page = 1;
                                      isLoading = true;
                                    });
                                  },
                                  icon: const Icon(Icons.refresh_rounded),
                                  tooltip: 'Reset filters',
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                              decoration: BoxDecoration(
                                color: _pageBg.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _panelBorder),
                              ),
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
                          ),

                          const SizedBox(height: 12),

                          if (hasMore)
                            _buildModalLoadMoreButton(
                              isLoading: isLoadingMore,
                              onPressed: loadMore,
                            )
                          else
                            _buildModalEndText("No more activities"),
                        ],
                      ),
              ),
              actions: [
                _buildDialogSecondaryButton(
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openApiUsageModal() {
    int page = 1;
    List<dynamic> modalRows = [];
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
              String? startDate;
              String? endDate;
              if (selectedDate != null) {
                startDate = selectedDate;
                endDate = selectedDate;
              } else if (selectedMonth != null) {
                final parts = selectedMonth!.split('-');
                if (parts.length == 2) {
                  final year = int.tryParse(parts[0]);
                  final month = int.tryParse(parts[1]);
                  if (year != null && month != null) {
                    final first = DateTime(year, month, 1);
                    final last = DateTime(year, month + 1, 0);
                    String fmt(DateTime d) =>
                        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
                    startDate = fmt(first);
                    endDate = fmt(last);
                  }
                }
              }
              final r = await ApiService.fetchApiUsagePaginated(
                startDate: startDate,
                endDate: endDate,
                page: page,
                perPage: _kApiUsagePerPage,
              );
              final items = List<dynamic>.from(r['items'] as List? ?? []);
              setModalState(() {
                modalRows = items;
                isLoading = false;
                hasMore = items.length == _kApiUsagePerPage;
              });
            }

            Future<void> loadMore() async {
              if (isLoadingMore || !hasMore) return;
              setModalState(() => isLoadingMore = true);
              page++;
              String? startDate;
              String? endDate;
              if (selectedDate != null) {
                startDate = selectedDate;
                endDate = selectedDate;
              } else if (selectedMonth != null) {
                final parts = selectedMonth!.split('-');
                if (parts.length == 2) {
                  final year = int.tryParse(parts[0]);
                  final month = int.tryParse(parts[1]);
                  if (year != null && month != null) {
                    final first = DateTime(year, month, 1);
                    final last = DateTime(year, month + 1, 0);
                    String fmt(DateTime d) =>
                        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
                    startDate = fmt(first);
                    endDate = fmt(last);
                  }
                }
              }
              final r = await ApiService.fetchApiUsagePaginated(
                startDate: startDate,
                endDate: endDate,
                page: page,
                perPage: _kApiUsagePerPage,
              );
              final newItems = List<dynamic>.from(r['items'] as List? ?? []);
              setModalState(() {
                modalRows.addAll(newItems);
                hasMore = newItems.length == _kApiUsagePerPage;
                isLoadingMore = false;
              });
            }

            Future<void> exportApiCsv() async {
              final headers = ['Endpoint', 'Hits', 'Avg Latency (ms)'];
              final rows = modalRows.map((row) {
                return [
                  "/${row['endpoint'] ?? 'unknown'}",
                  (row['hits'] ?? 0).toString(),
                  (double.tryParse(row['avg_latency']?.toString() ?? '0') ?? 0)
                      .toStringAsFixed(0),
                ];
              }).toList();
              await _exportToCSV('API_Traffic', headers, rows);
            }

            String fmtDate(String iso) {
              final parsed = DateTime.tryParse(iso);
              if (parsed == null) return iso;
              return "${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}";
            }

            if (isLoading) loadInitial();

            return AlertDialog(
              backgroundColor: _panelBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              title: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: _pageBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _panelBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: primaryBrand.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.api_rounded,
                        color: primaryBrand,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "All API Traffic",
                            style: TextStyle(
                              color: _mainText,
                              fontWeight: FontWeight.w900,
                              fontSize: 19,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Endpoint requests and latency metrics",
                            style: TextStyle(
                              color: _mutedText,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: modalRows.isEmpty ? null : exportApiCsv,
                      icon: const Icon(Icons.download_rounded, size: 17),
                      label: const Text("Export CSV"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _mainText,
                        side: BorderSide(color: _panelBorder),
                        backgroundColor: _panelBg,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: 600,
                height: 500,
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _pageBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _panelBorder),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.now(),
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime.now(),
                                      );
                                      if (picked != null) {
                                        setModalState(() {
                                          selectedDate = fmtDate(picked.toIso8601String());
                                          selectedMonth = null;
                                          page = 1;
                                          isLoading = true;
                                        });
                                      }
                                    },
                                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                                    label: Text(selectedDate == null ? "Select Date" : fmtDate(selectedDate!)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _mainText,
                                      side: BorderSide(color: _panelBorder),
                                      backgroundColor: _panelBg,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
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
                                          selectedMonth =
                                              "${picked.year}-${picked.month.toString().padLeft(2, '0')}";
                                          selectedDate = null;
                                          page = 1;
                                          isLoading = true;
                                        });
                                      }
                                    },
                                    icon: const Icon(Icons.date_range_rounded, size: 18),
                                    label: Text(selectedMonth ?? "Select Month"),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _mainText,
                                      side: BorderSide(color: _panelBorder),
                                      backgroundColor: _panelBg,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton.filledTonal(
                                  onPressed: () {
                                    setModalState(() {
                                      selectedDate = null;
                                      selectedMonth = null;
                                      page = 1;
                                      isLoading = true;
                                    });
                                  },
                                  icon: const Icon(Icons.refresh_rounded),
                                  tooltip: 'Reset filters',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                              decoration: BoxDecoration(
                                color: _pageBg.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _panelBorder),
                              ),
                              child: ListView.builder(
                                itemCount: modalRows.length,
                                itemBuilder: (context, index) {
                                  final log = modalRows[index];
                                  final latency = double.tryParse(
                                        log['avg_latency']?.toString() ?? '0',
                                      ) ??
                                      0;
                                  final isSlow = latency > 400;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: _panelBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: _panelBorder),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            "/${log['endpoint'] ?? 'unknown'}",
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                              color: _mainText,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          "${log['hits'] ?? 0} reqs",
                                          style: TextStyle(color: _mutedText),
                                        ),
                                        const SizedBox(width: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSlow
                                                ? dangerRed.withValues(alpha: 0.1)
                                                : successEmerald.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: Text(
                                            "${latency.toStringAsFixed(0)} ms",
                                            style: TextStyle(
                                              color: isSlow ? dangerRed : successEmerald,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (hasMore)
                            _buildModalLoadMoreButton(
                              isLoading: isLoadingMore,
                              onPressed: loadMore,
                            )
                          else
                            _buildModalEndText("No more API traffic logs"),
                        ],
                      ),
              ),
              actions: [
                _buildDialogSecondaryButton(
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openSystemHealthModal() {
    int page = 1;
    List<dynamic> modalRows = [];
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
              String? startDate;
              String? endDate;
              if (selectedDate != null) {
                startDate = selectedDate;
                endDate = selectedDate;
              } else if (selectedMonth != null) {
                final parts = selectedMonth!.split('-');
                if (parts.length == 2) {
                  final year = int.tryParse(parts[0]);
                  final month = int.tryParse(parts[1]);
                  if (year != null && month != null) {
                    final first = DateTime(year, month, 1);
                    final last = DateTime(year, month + 1, 0);
                    String fmt(DateTime d) =>
                        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
                    startDate = fmt(first);
                    endDate = fmt(last);
                  }
                }
              }
              final r = await ApiService.fetchErrorLogsPaginated(
                startDate: startDate,
                endDate: endDate,
                page: page,
                perPage: _kErrorLogsPerPage,
              );
              final items = List<dynamic>.from(r['items'] as List? ?? []);
              setModalState(() {
                modalRows = items;
                isLoading = false;
                hasMore = items.length == _kErrorLogsPerPage;
              });
            }

            Future<void> loadMore() async {
              if (isLoadingMore || !hasMore) return;
              setModalState(() => isLoadingMore = true);
              page++;
              String? startDate;
              String? endDate;
              if (selectedDate != null) {
                startDate = selectedDate;
                endDate = selectedDate;
              } else if (selectedMonth != null) {
                final parts = selectedMonth!.split('-');
                if (parts.length == 2) {
                  final year = int.tryParse(parts[0]);
                  final month = int.tryParse(parts[1]);
                  if (year != null && month != null) {
                    final first = DateTime(year, month, 1);
                    final last = DateTime(year, month + 1, 0);
                    String fmt(DateTime d) =>
                        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
                    startDate = fmt(first);
                    endDate = fmt(last);
                  }
                }
              }
              final r = await ApiService.fetchErrorLogsPaginated(
                startDate: startDate,
                endDate: endDate,
                page: page,
                perPage: _kErrorLogsPerPage,
              );
              final newItems = List<dynamic>.from(r['items'] as List? ?? []);
              setModalState(() {
                modalRows.addAll(newItems);
                hasMore = newItems.length == _kErrorLogsPerPage;
                isLoadingMore = false;
              });
            }

            Future<void> exportSystemCsv() async {
              final headers = ['Message', 'Endpoint'];
              final rows = modalRows.map((row) {
                return [
                  (row['message'] ?? 'Unhandled error').toString(),
                  "/${row['endpoint'] ?? 'unknown'}",
                ];
              }).toList();
              await _exportToCSV('System_Health_Logs', headers, rows);
            }

            String fmtDate(String iso) {
              final parsed = DateTime.tryParse(iso);
              if (parsed == null) return iso;
              return "${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}";
            }

            if (isLoading) loadInitial();

            return AlertDialog(
              backgroundColor: _panelBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              title: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: _pageBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _panelBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: dangerRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.health_and_safety_rounded,
                        color: dangerRed,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "All System Health Logs",
                            style: TextStyle(
                              color: _mainText,
                              fontWeight: FontWeight.w900,
                              fontSize: 19,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Critical errors and warnings from the system",
                            style: TextStyle(
                              color: _mutedText,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: modalRows.isEmpty ? null : exportSystemCsv,
                      icon: const Icon(Icons.download_rounded, size: 17),
                      label: const Text("Export CSV"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _mainText,
                        side: BorderSide(color: _panelBorder),
                        backgroundColor: _panelBg,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: 600,
                height: 500,
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _pageBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _panelBorder),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.now(),
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime.now(),
                                      );
                                      if (picked != null) {
                                        setModalState(() {
                                          selectedDate = fmtDate(picked.toIso8601String());
                                          selectedMonth = null;
                                          page = 1;
                                          isLoading = true;
                                        });
                                      }
                                    },
                                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                                    label: Text(selectedDate == null ? "Select Date" : fmtDate(selectedDate!)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _mainText,
                                      side: BorderSide(color: _panelBorder),
                                      backgroundColor: _panelBg,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
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
                                          selectedMonth =
                                              "${picked.year}-${picked.month.toString().padLeft(2, '0')}";
                                          selectedDate = null;
                                          page = 1;
                                          isLoading = true;
                                        });
                                      }
                                    },
                                    icon: const Icon(Icons.date_range_rounded, size: 18),
                                    label: Text(selectedMonth ?? "Select Month"),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _mainText,
                                      side: BorderSide(color: _panelBorder),
                                      backgroundColor: _panelBg,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton.filledTonal(
                                  onPressed: () {
                                    setModalState(() {
                                      selectedDate = null;
                                      selectedMonth = null;
                                      page = 1;
                                      isLoading = true;
                                    });
                                  },
                                  icon: const Icon(Icons.refresh_rounded),
                                  tooltip: 'Reset filters',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                              decoration: BoxDecoration(
                                color: _pageBg.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _panelBorder),
                              ),
                              child: ListView.builder(
                                itemCount: modalRows.length,
                                itemBuilder: (context, index) {
                                  final error = modalRows[index];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: dangerRed.withValues(alpha: 0.04),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: dangerRed.withValues(alpha: 0.18),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (error['message'] ?? 'Unhandled error')
                                              .toString(),
                                          style: const TextStyle(
                                            color: dangerRed,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          "/${error['endpoint'] ?? 'unknown'}",
                                          style: TextStyle(
                                            color: _mutedText,
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (hasMore)
                            _buildModalLoadMoreButton(
                              isLoading: isLoadingMore,
                              onPressed: loadMore,
                            )
                          else
                            _buildModalEndText("No more system health logs"),
                        ],
                      ),
              ),
              actions: [
                _buildDialogSecondaryButton(
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openPerformanceModal() {
    int page = 1;
    List<dynamic> modalRows = [];
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
              String? startDate;
              String? endDate;
              if (selectedDate != null) {
                startDate = selectedDate;
                endDate = selectedDate;
              } else if (selectedMonth != null) {
                final parts = selectedMonth!.split('-');
                if (parts.length == 2) {
                  final year = int.tryParse(parts[0]);
                  final month = int.tryParse(parts[1]);
                  if (year != null && month != null) {
                    final first = DateTime(year, month, 1);
                    final last = DateTime(year, month + 1, 0);
                    String fmt(DateTime d) =>
                        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
                    startDate = fmt(first);
                    endDate = fmt(last);
                  }
                }
              }
              final r = await ApiService.fetchPerformanceMetricsPaginated(
                startDate: startDate,
                endDate: endDate,
                page: page,
                perPage: _kPerformancePerPage,
              );
              final items = List<dynamic>.from(r['items'] as List? ?? []);
              setModalState(() {
                modalRows = items;
                isLoading = false;
                hasMore = items.length == _kPerformancePerPage;
              });
            }

            Future<void> loadMore() async {
              if (isLoadingMore || !hasMore) return;
              setModalState(() => isLoadingMore = true);
              page++;
              String? startDate;
              String? endDate;
              if (selectedDate != null) {
                startDate = selectedDate;
                endDate = selectedDate;
              } else if (selectedMonth != null) {
                final parts = selectedMonth!.split('-');
                if (parts.length == 2) {
                  final year = int.tryParse(parts[0]);
                  final month = int.tryParse(parts[1]);
                  if (year != null && month != null) {
                    final first = DateTime(year, month, 1);
                    final last = DateTime(year, month + 1, 0);
                    String fmt(DateTime d) =>
                        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
                    startDate = fmt(first);
                    endDate = fmt(last);
                  }
                }
              }
              final r = await ApiService.fetchPerformanceMetricsPaginated(
                startDate: startDate,
                endDate: endDate,
                page: page,
                perPage: _kPerformancePerPage,
              );
              final newItems = List<dynamic>.from(r['items'] as List? ?? []);
              setModalState(() {
                modalRows.addAll(newItems);
                hasMore = newItems.length == _kPerformancePerPage;
                isLoadingMore = false;
              });
            }

            Future<void> exportPerformanceCsv() async {
              final headers = ['Type', 'Name', 'Duration (ms)'];
              final rows = modalRows.map((row) {
                return [
                  (row['kind'] ?? '').toString(),
                  (row['name'] ?? '').toString(),
                  (row['duration_ms'] ?? 0).toString(),
                ];
              }).toList();
              await _exportToCSV('Client_Performance', headers, rows);
            }

            String fmtDate(String iso) {
              final parsed = DateTime.tryParse(iso);
              if (parsed == null) return iso;
              return "${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}";
            }

            if (isLoading) loadInitial();

            return AlertDialog(
              backgroundColor: _panelBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              title: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: _pageBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _panelBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: successEmerald.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.speed_rounded,
                        color: successEmerald,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "All Client Performance Metrics",
                            style: TextStyle(
                              color: _mainText,
                              fontWeight: FontWeight.w900,
                              fontSize: 19,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Frontend timing and route performance events",
                            style: TextStyle(
                              color: _mutedText,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: modalRows.isEmpty ? null : exportPerformanceCsv,
                      icon: const Icon(Icons.download_rounded, size: 17),
                      label: const Text("Export CSV"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _mainText,
                        side: BorderSide(color: _panelBorder),
                        backgroundColor: _panelBg,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: 600,
                height: 500,
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _pageBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _panelBorder),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.now(),
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime.now(),
                                      );
                                      if (picked != null) {
                                        setModalState(() {
                                          selectedDate = fmtDate(picked.toIso8601String());
                                          selectedMonth = null;
                                          page = 1;
                                          isLoading = true;
                                        });
                                      }
                                    },
                                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                                    label: Text(selectedDate == null ? "Select Date" : fmtDate(selectedDate!)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _mainText,
                                      side: BorderSide(color: _panelBorder),
                                      backgroundColor: _panelBg,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
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
                                          selectedMonth =
                                              "${picked.year}-${picked.month.toString().padLeft(2, '0')}";
                                          selectedDate = null;
                                          page = 1;
                                          isLoading = true;
                                        });
                                      }
                                    },
                                    icon: const Icon(Icons.date_range_rounded, size: 18),
                                    label: Text(selectedMonth ?? "Select Month"),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _mainText,
                                      side: BorderSide(color: _panelBorder),
                                      backgroundColor: _panelBg,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton.filledTonal(
                                  onPressed: () {
                                    setModalState(() {
                                      selectedDate = null;
                                      selectedMonth = null;
                                      page = 1;
                                      isLoading = true;
                                    });
                                  },
                                  icon: const Icon(Icons.refresh_rounded),
                                  tooltip: 'Reset filters',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                              decoration: BoxDecoration(
                                color: _pageBg.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _panelBorder),
                              ),
                              child: ListView.builder(
                                itemCount: modalRows.length,
                                itemBuilder: (context, index) {
                                  final row = modalRows[index];
                                  final durationMs =
                                      int.tryParse(row['duration_ms']?.toString() ?? '0') ?? 0;
                                  final sevColor = durationMs > 1500
                                      ? warningAmber
                                      : successEmerald;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: _panelBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: _panelBorder),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.timeline_rounded,
                                          color: sevColor,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            '${row['kind'] ?? ''} · ${row['name'] ?? ''} · $durationMs ms',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                              color: _mainText,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (hasMore)
                            _buildModalLoadMoreButton(
                              isLoading: isLoadingMore,
                              onPressed: loadMore,
                            )
                          else
                            _buildModalEndText("No more performance logs"),
                        ],
                      ),
              ),
              actions: [
                _buildDialogSecondaryButton(
                  onPressed: () => Navigator.pop(context),
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

    return Column(
      children: [
        ...apiUsageData.map((log) {
          final latency =
              double.tryParse(log['avg_latency']?.toString() ?? '0') ?? 0;

          final isSlow = latency > 400;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _panelBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _panelBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: _isDark
                        ? Colors.white.withOpacity(0.08)
                        : darkSlate.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "GET",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: _mainText,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    "/${log['endpoint']}",
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _mainText,
                    ),
                  ),
                ),
                Text(
                  "${log['hits']} reqs",
                  style: TextStyle(color: _mutedText, fontWeight: FontWeight.w700),
                ),
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
                  child: Text(
                    "${latency.toStringAsFixed(0)} ms",
                    style: TextStyle(
                      color: isSlow ? dangerRed : successEmerald,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(growable: false),

        const SizedBox(height: 10),

        if (_apiUsageLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),

        const SizedBox(height: 6),
        _buildStandardPaginationBar(
          summary: "Loaded ${apiUsageData.length} of $_apiUsageTotal API rows",
          pageLabel: "$_apiUsagePage/$_apiUsageLastPage",
          currentPage: _apiUsagePage,
          totalPages: _apiUsageLastPage,
          onJumpToPage: (page) => unawaited(_goToApiUsagePage(page)),
          canGoPrev: _apiUsagePage > 1,
          canGoNext: _apiUsagePage < _apiUsageLastPage,
          onPrev: () => unawaited(_goToApiUsagePage(_apiUsagePage - 1)),
          onNext: () => unawaited(_goToApiUsagePage(_apiUsagePage + 1)),
        ),
      ],
    );
  }

  void _applyErrorLogsMeta(Map<String, dynamic> m) {
    _errorLogsLastPage = (m['last_page'] as num?)?.toInt() ?? 1;
    _errorLogsTotal = (m['total'] as num?)?.toInt() ?? 0;
    final cp = (m['current_page'] as num?)?.toInt();
    if (cp != null) _errorLogsPage = cp;
  }

  void _applyApiUsageMeta(Map<String, dynamic> m) {
    _apiUsageLastPage = (m['last_page'] as num?)?.toInt() ?? 1;
    _apiUsageTotal = (m['total'] as num?)?.toInt() ?? 0;
    final cp = (m['current_page'] as num?)?.toInt();
    if (cp != null) _apiUsagePage = cp;
  }

  void _applyPerformanceMeta(Map<String, dynamic> m) {
    _performanceLastPage = (m['last_page'] as num?)?.toInt() ?? 1;
    _performanceTotal = (m['total'] as num?)?.toInt() ?? 0;
    final cp = (m['current_page'] as num?)?.toInt();
    if (cp != null) _performancePage = cp;
  }

  Future<void> _reloadApiUsage({bool reset = false}) async {
    if (reset) {
      _apiUsagePage = 1;
      apiUsageData = [];
    }
    setState(() => _apiUsageLoading = true);
    try {
      final r = await ApiService.fetchApiUsagePaginated(
        page: _apiUsagePage,
        perPage: _kApiUsagePerPage,
      );
      if (!mounted) return;
      setState(() {
        final items = r['items'] as List<dynamic>;
        apiUsageData = reset ? items : [...apiUsageData, ...items];
        final meta = r['meta'];
        if (meta is Map) {
          _applyApiUsageMeta(Map<String, dynamic>.from(meta));
        }
        _apiUsageLoading = false;
        _apiUsageLoadingMore = false;
      });
    } catch (e) {
      debugPrint('API usage reload: $e');
      if (mounted) {
        setState(() {
          _apiUsageLoading = false;
          _apiUsageLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMoreApiUsage() async {
    if (_apiUsageLoadingMore || _apiUsagePage >= _apiUsageLastPage) return;
    setState(() => _apiUsageLoadingMore = true);
    _apiUsagePage++;
    await _reloadApiUsage(reset: false);
  }

  Future<void> _goToApiUsagePage(int page) async {
    if (page < 1 || page > _apiUsageLastPage) return;
    setState(() => _apiUsageLoading = true);
    try {
      final r = await ApiService.fetchApiUsagePaginated(
        page: page,
        perPage: _kApiUsagePerPage,
      );
      if (!mounted) return;
      setState(() {
        apiUsageData = List<dynamic>.from(r['items'] as List? ?? []);
        final meta = r['meta'];
        if (meta is Map) {
          _applyApiUsageMeta(Map<String, dynamic>.from(meta));
        } else {
          _apiUsagePage = page;
        }
        _apiUsageLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _apiUsageLoading = false);
    }
  }

  Future<void> _reloadPerformanceMetrics({bool reset = false}) async {
    if (reset) {
      _performancePage = 1;
      performanceMetrics = [];
    }
    setState(() => _performanceLoading = true);
    try {
      final r = await ApiService.fetchPerformanceMetricsPaginated(
        page: _performancePage,
        perPage: _kPerformancePerPage,
      );
      if (!mounted) return;
      setState(() {
        final items = r['items'] as List<dynamic>;
        performanceMetrics = reset ? items : [...performanceMetrics, ...items];
        final meta = r['meta'];
        if (meta is Map) {
          _applyPerformanceMeta(Map<String, dynamic>.from(meta));
        }
        _performanceLoading = false;
        _performanceLoadingMore = false;
      });
    } catch (e) {
      debugPrint('Performance reload: $e');
      if (mounted) {
        setState(() {
          _performanceLoading = false;
          _performanceLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMorePerformanceMetrics() async {
    if (_performanceLoadingMore || _performancePage >= _performanceLastPage) {
      return;
    }
    setState(() => _performanceLoadingMore = true);
    _performancePage++;
    await _reloadPerformanceMetrics(reset: false);
  }

  Future<void> _goToPerformancePage(int page) async {
    if (page < 1 || page > _performanceLastPage) return;
    setState(() => _performanceLoading = true);
    try {
      final r = await ApiService.fetchPerformanceMetricsPaginated(
        page: page,
        perPage: _kPerformancePerPage,
      );
      if (!mounted) return;
      setState(() {
        performanceMetrics = List<dynamic>.from(r['items'] as List? ?? []);
        final meta = r['meta'];
        if (meta is Map) {
          _applyPerformanceMeta(Map<String, dynamic>.from(meta));
        } else {
          _performancePage = page;
        }
        _performanceLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _performanceLoading = false);
    }
  }

  Future<void> _reloadErrorLogs({bool resetPage = false, bool append = false}) async {
    if (resetPage) {
      _errorLogsPage = 1;
      errorLogs = [];
    }
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
        final items = r['items'] as List<dynamic>;
        errorLogs = append ? [...errorLogs, ...items] : items;
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

  Future<void> _loadMoreErrorLogs() async {
    if (_errorLogsLoading || _errorLogsPage >= _errorLogsLastPage) return;
    setState(() => _errorLogsLoading = true);
    _errorLogsPage++;
    await _reloadErrorLogs(append: true);
  }

  Future<void> _goToErrorLogsPage(int page) async {
    if (page < 1 || page > _errorLogsLastPage) return;
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
        page: page,
        perPage: _kErrorLogsPerPage,
      );
      if (!mounted) return;
      setState(() {
        errorLogs = List<dynamic>.from(r['items'] as List? ?? []);
        final meta = r['meta'];
        if (meta is Map) {
          _applyErrorLogsMeta(Map<String, dynamic>.from(meta));
        } else {
          _errorLogsPage = page;
        }
        _errorLogsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _errorLogsLoading = false);
    }
  }

  Future<void> _goToActivityPage(int page) async {
    if (page < 1) return;
    setState(() => _isLoadingMore = true);
    try {
      final logs = await ApiService.fetchActivityLogs(page);
      if (!mounted) return;
      setState(() {
        _activityPage = page;
        activityLogs = logs;
        _hasMoreActivity = logs.length == 10;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _pickErrorDate(TextEditingController controller) async {
    final now = DateTime.now();
    DateTime initial = now;
    final raw = controller.text.trim();
    if (raw.isNotEmpty) {
      initial = DateTime.tryParse(raw) ?? now;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  surface: _panelBg,
                ),
          ),
          child: child,
        );
      },
    );
    if (picked == null) return;
    final formatted =
        "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
    setState(() => controller.text = formatted);
  }

  Widget _errorFilterField({
    required TextEditingController controller,
    required String hint,
    IconData? icon,
    double width = 180,
    VoidCallback? onTap,
    bool readOnly = false,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        onTap: onTap,
        style: TextStyle(
          color: _mainText,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: _pageBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          hintStyle: TextStyle(color: _mutedText, fontWeight: FontWeight.w500),
          prefixIcon:
              icon == null ? null : Icon(icon, size: 18, color: _mutedText),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _panelBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _panelBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primaryBrand, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorLogsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _panelBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _panelBorder),
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _errorSeverity,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: _pageBg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _panelBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _panelBorder),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: primaryBrand, width: 1.5),
                    ),
                  ),
                  dropdownColor: _panelBg,
                  style: TextStyle(color: _mainText, fontWeight: FontWeight.w600),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All severities')),
                    DropdownMenuItem(value: 'critical', child: Text('Critical')),
                    DropdownMenuItem(value: 'error', child: Text('Error')),
                    DropdownMenuItem(value: 'warning', child: Text('Warning')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _errorSeverity = v);
                  },
                ),
              ),
              _errorFilterField(
                controller: _errorTypeController,
                hint: 'Error type',
                icon: Icons.bug_report_outlined,
                width: 180,
              ),
              _errorFilterField(
                controller: _errorStartController,
                hint: 'Start date',
                icon: Icons.calendar_month_outlined,
                width: 150,
                readOnly: true,
                onTap: () => _pickErrorDate(_errorStartController),
              ),
              _errorFilterField(
                controller: _errorEndController,
                hint: 'End date',
                icon: Icons.event_outlined,
                width: 150,
                readOnly: true,
                onTap: () => _pickErrorDate(_errorEndController),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _errorSeverity = 'all';
                    _errorTypeController.clear();
                    _errorStartController.clear();
                    _errorEndController.clear();
                  });
                  _reloadErrorLogs(resetPage: true);
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reset'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  side: BorderSide(color: _panelBorder),
                  foregroundColor: _mainText,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: _pageBg,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _reloadErrorLogs(resetPage: true),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Apply Filters'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  backgroundColor: primaryBrand,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
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
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: _buildStandardPaginationBar(
        summary: "Loaded ${errorLogs.length} of $_errorLogsTotal system errors",
        pageLabel: "$_errorLogsPage/$_errorLogsLastPage",
        currentPage: _errorLogsPage,
        totalPages: _errorLogsLastPage,
        onJumpToPage: (page) => unawaited(_goToErrorLogsPage(page)),
        canGoPrev: _errorLogsPage > 1,
        canGoNext: _errorLogsPage < _errorLogsLastPage,
        onPrev: () => unawaited(_goToErrorLogsPage(_errorLogsPage - 1)),
        onNext: () => unawaited(_goToErrorLogsPage(_errorLogsPage + 1)),
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
      children: [
        ...performanceMetrics.map((row) {
          final sevColor = (row['duration_ms'] as int? ?? 0) > 1500
              ? warningAmber
              : successEmerald;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _panelBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _panelBorder),
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
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: _mainText,
                        ),
                      ),
                      Text(
                        '${row['duration_ms'] ?? 0} ms · ${row['user_email'] ?? row['user_name'] ?? 'guest'}',
                        style: TextStyle(fontSize: 11, color: _mutedText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(growable: false),
        if (_performanceLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        const SizedBox(height: 6),
        _buildStandardPaginationBar(
          summary: "Loaded ${performanceMetrics.length} of $_performanceTotal metrics",
          pageLabel: "$_performancePage/$_performanceLastPage",
          currentPage: _performancePage,
          totalPages: _performanceLastPage,
          onJumpToPage: (page) => unawaited(_goToPerformancePage(page)),
          canGoPrev: _performancePage > 1,
          canGoNext: _performancePage < _performanceLastPage,
          onPrev: () => unawaited(_goToPerformancePage(_performancePage - 1)),
          onNext: () => unawaited(_goToPerformancePage(_performancePage + 1)),
        ),
      ],
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

  Widget _buildOperationsMonitorView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bentoBox(
            "API Traffic & Latency",
            "Real-time endpoint performance monitoring.",
            _buildApiUsageTable(),
            trailingIcon: Icons.visibility,
            onTrailingTap: _openApiUsageModal,
          ),
          const SizedBox(height: 28),
          _bentoBox(
            "Activity Timeline",
            "Live feed of user interactions.",
            _buildActivityLogsTable(),
            trailingIcon: Icons.visibility,
            onTrailingTap: _openActivityModal,
          ),
          const SizedBox(height: 28),
          _bentoBox(
            "System Health Status",
            "Recent critical alerts and warnings.",
            _buildErrorLogsSection(),
            trailingIcon: Icons.visibility,
            onTrailingTap: _openSystemHealthModal,
          ),
          const SizedBox(height: 28),
          _bentoBox(
            "Client Performance",
            "Screen transitions and slow API calls from the app.",
            _buildPerformanceMetricsTable(),
            trailingIcon: Icons.visibility,
            onTrailingTap: _openPerformanceModal,
          ),
        ],
      ),
    );
  }

  // --- HEADER & SIDEBAR ---
  String get _currentHeaderTitle {
    switch (_selectedIndex) {
      case 1:
        return "User Directory";
      case 2:
        return "Recipe Library";
      case 3:
        return "Operations Monitor";
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
      case 3:
        return "Track API traffic, app activity, system health, and client performance.";
      default:
        return "Real-time analytics and platform monitoring.";
    }
  }

  void _openAdminSettings() {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _panelBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            "Admin Settings",
            style: TextStyle(fontWeight: FontWeight.w900, color: _mainText),
          ),
          content: Consumer<ThemeNotifier>(
            builder: (context, tn, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Appearance",
                    style: TextStyle(
                      color: _mutedText,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_rounded),
                        label: Text("Light"),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_rounded),
                        label: Text("Dark"),
                      ),
                    ],
                    selected: {tn.mode == ThemeMode.system ? ThemeMode.light : tn.mode},
                    onSelectionChanged: (value) {
                      final selected = value.first;
                      tn.setMode(selected);
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return cs.primary.withOpacity(0.18);
                        }
                        return _pageBg;
                      }),
                      foregroundColor: WidgetStatePropertyAll(_mainText),
                      side: WidgetStatePropertyAll(BorderSide(color: _panelBorder)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Default app theme is now Light mode.",
                    style: TextStyle(color: _mutedText, fontSize: 12),
                  ),
                ],
              );
            },
          ),
          actions: [
            _buildDialogSecondaryButton(
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openAutoTagTool() async {
    final nameController = TextEditingController();
    final ingredientsController = TextEditingController();
    final instructionsController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _panelBg,
          title: Text(
            'AI Auto-Tag Tool',
            style: TextStyle(color: _mainText, fontWeight: FontWeight.w900),
          ),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  label: 'Recipe name',
                  icon: Icons.restaurant_menu_rounded,
                  controller: nameController,
                ),
                const SizedBox(height: 10),
                _buildDialogTextField(
                  label: 'Ingredients (comma separated)',
                  icon: Icons.set_meal_rounded,
                  controller: ingredientsController,
                ),
                const SizedBox(height: 10),
                _buildDialogTextField(
                  label: 'Instructions (short)',
                  icon: Icons.notes_rounded,
                  controller: instructionsController,
                ),
              ],
            ),
          ),
          actions: [
            _buildDialogSecondaryButton(
              onPressed: () => Navigator.pop(ctx),
            ),
            _buildDialogPrimaryButton(
              label: 'Generate',
              icon: Icons.auto_awesome_rounded,
              onPressed: () async {
                try {
                  final ingredients = ingredientsController.text
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList();
                  final out = await ApiService.adminAutoTagRecipe(
                    name: nameController.text.trim(),
                    instructions: instructionsController.text.trim(),
                    ingredients: ingredients,
                  );
                  if (!mounted) return;
                  final data = Map<String, dynamic>.from(
                    out['data'] as Map? ?? <String, dynamic>{},
                  );
                  _showSnackBar(
                    "AI suggestion: ${data['category'] ?? '-'} • ${data['difficulty'] ?? '-'} • ~${data['cooking_time'] ?? '-'} min",
                  );
                } catch (e) {
                  _showSnackBar('Auto-tag failed: $e', isError: true);
                }
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader({
    bool isCompactLayout = false,
    VoidCallback? onOpenMenu,
  }) {
    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = width < 1200 ? 24.0 : 40.0;
    return Container(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 20, horizontalPadding, 18),
      decoration: BoxDecoration(
        color: _panelBg,
        border: Border(bottom: BorderSide(color: _panelBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _brandSoft,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _brandStroke),
                      ),
                      child: Text(
                        "ADMIN CONTROL CENTER",
                        style: TextStyle(
                          color: primaryBrand,
                          fontSize: 10.5,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _currentHeaderTitle,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: _mainText,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentHeaderSubtitle,
                      style: TextStyle(
                        color: _mutedText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCompactLayout) ...[
                const SizedBox(width: 8),
                _headerIconAction(
                  tooltip: "Open navigation",
                  icon: Icons.menu_rounded,
                  onPressed: onOpenMenu ?? () {},
                ),
                const SizedBox(width: 8),
              ] else
                const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _pageBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _panelBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: successEmerald,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Live",
                      style: TextStyle(
                        color: _mainText,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _headerIconAction(
                    tooltip: "Admin Settings",
                    icon: Icons.settings_rounded,
                    onPressed: _openAdminSettings,
                  ),
                  const SizedBox(width: 8),
                  _headerIconAction(
                    tooltip: "Refresh Data",
                    icon: Icons.sync_rounded,
                    onPressed: () {
                      unawaited(
                        _refreshCoreDataInBackground(
                          includeAnalytics: true,
                          showToast: true,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerIconAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _panelBorder),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: _mutedText, size: 19),
        tooltip: tooltip,
        style: IconButton.styleFrom(
          padding: const EdgeInsets.all(10),
          minimumSize: const Size(40, 40),
        ),
      ),
    );
  }

  Widget _headerActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool isPrimary = false,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary ? primaryBrand : _panelBg,
        foregroundColor: isPrimary ? Colors.white : _mainText,
        elevation: 0,
        side: isPrimary ? null : BorderSide(color: _panelBorder),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        minimumSize: const Size(0, 40),
        textStyle: const TextStyle(fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final compact = MediaQuery.of(context).size.width < 1300;
    final cards = [
      _statCard("Total Users", totalUsers, Icons.people_alt_rounded, primaryBrand),
      _statCard("Published Recipes", totalRecipes, Icons.menu_book_rounded, warningAmber),
      _statCard("Total Views", activityStats?['views'] ?? 0, Icons.visibility_rounded, successEmerald),
      _statCard("Total Favorites", activityStats?['favorites'] ?? 0, Icons.favorite_rounded, dangerRed),
    ];
    if (compact) {
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: cards.map((c) => SizedBox(width: 280, child: c)).toList(),
      );
    }
    return Row(
      children: cards
          .asMap()
          .entries
          .map((entry) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: entry.key == cards.length - 1 ? 0 : 16),
                  child: entry.value,
                ),
              ))
          .toList(),
    );
  }

  Widget _statCard(String title, dynamic value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: _isDark ? 0.20 : 0.10),
            _panelBg,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: _isDark ? 0.32 : 0.24)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: _isDark ? 0.20 : 0.10),
            blurRadius: 20,
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: _isDark ? 0.08 : 0.66),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  "LIVE",
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: _mainText,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: _mutedText,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 284,
      decoration: BoxDecoration(
        color: _isDark ? _sidebarBg.withValues(alpha: 0.92) : const Color(0xFF222534),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 28),
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                      decoration: BoxDecoration(
                        color: _sidebarSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _sidebarBorder),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: primaryBrand.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.restaurant_menu_rounded,
                              color: primaryBrandLight,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Core Admin",
                                  style: TextStyle(
                                    color: _sidebarText,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "System online",
                                  style: TextStyle(
                                    color: successEmerald,
                                    fontSize: 10.8,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "NAVIGATION",
                          style: TextStyle(
                            color: _sidebarMuted,
                            fontSize: 10.5,
                            letterSpacing: 0.9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
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
                        _navItem(
                          Icons.monitor_heart_rounded,
                          "Operations",
                          _selectedIndex == 3,
                          () => setState(() => _selectedIndex = 3),
                        ),
                        const SizedBox(height: 16),
                        Divider(color: _sidebarBorder, height: 1),
                        const SizedBox(height: 14),
                        Text(
                          "QUICK ACTIONS",
                          style: TextStyle(
                            color: _sidebarMuted,
                            fontSize: 10.5,
                            letterSpacing: 0.9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _sidebarActionButton(
                          icon: Icons.set_meal_rounded,
                          label: "Add Ingredient",
                          onTap: _showAddIngredientDialog,
                        ),
                        _sidebarActionButton(
                          icon: Icons.person_add_rounded,
                          label: "New User",
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const CreateUserScreen()),
                          ).then((_) => _refreshCoreDataInBackground()),
                        ),
                        _sidebarActionButton(
                          icon: Icons.auto_awesome_rounded,
                          label: "AI Auto-Tag",
                          onTap: _openAutoTagTool,
                        ),
                        _sidebarActionButton(
                          icon: Icons.add_rounded,
                          label: "Add Recipe",
                          isPrimary: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const RecipeFormScreen()),
                          ).then((_) => _refreshCoreDataInBackground()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextButton.icon(
              onPressed: () async {
                await ApiService.logout();
                if (!mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              icon: const Icon(Icons.power_settings_new_rounded, size: 18),
              label: const Text(
                "Sign Out",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: TextButton.styleFrom(
                foregroundColor: dangerRed,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: _sidebarSurface,
                side: BorderSide(color: dangerRed.withValues(alpha: 0.28)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    if (isPrimary) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 4),
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Add Recipe",
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryBrand,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            minimumSize: const Size(0, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: _sidebarBorder),
        ),
        tileColor: _sidebarSurface.withValues(alpha: 0.65),
        leading: Icon(icon, size: 16, color: _sidebarText.withValues(alpha: 0.90)),
        title: Text(
          label,
          style: TextStyle(
            color: _sidebarText.withValues(alpha: 0.95),
            fontSize: 12.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          size: 16,
          color: _sidebarMuted,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _navItem(
    IconData icon,
    String label,
    bool active,
    VoidCallback onTap,
  ) {
    final iconColor = active
        ? primaryBrand
        : _sidebarText.withValues(alpha: _isDark ? 0.74 : 0.62);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        gradient: active
            ? LinearGradient(
                colors: [
                  primaryBrand.withValues(alpha: 0.22),
                  primaryBrand.withValues(alpha: 0.10),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              )
            : null,
        color: active ? null : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? primaryBrand.withValues(alpha: 0.55) : Colors.transparent,
        ),
      ),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(
          icon,
          color: iconColor,
          size: 18,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: active
                ? _sidebarText
                : _sidebarText.withValues(alpha: _isDark ? 0.74 : 0.62),
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            fontSize: 13,
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
              style: TextStyle(
                color: _mutedText,
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
