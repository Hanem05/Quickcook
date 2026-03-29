// lib/models/admin_stats.dart

class AdminStats {
  final int totalUsers;
  final int totalRecipes;
  final List<CategoryStat> categoryDistribution;

  AdminStats({
    required this.totalUsers,
    required this.totalRecipes,
    required this.categoryDistribution,
  });

  factory AdminStats.fromJson(Map<String, dynamic> json) {
    return AdminStats(
      totalUsers: json['total_users'] ?? 0,
      totalRecipes: json['total_recipes'] ?? 0,
      categoryDistribution:
          (json['category_distribution'] as List?)
              ?.map((item) => CategoryStat.fromJson(item))
              .toList() ??
          [],
    );
  }
}

class CategoryStat {
  final String category;
  final int count;

  CategoryStat({required this.category, required this.count});

  factory CategoryStat.fromJson(Map<String, dynamic> json) {
    return CategoryStat(
      category: json['category'] ?? 'Uncategorized',
      count: json['count'] ?? 0,
    );
  }
}
