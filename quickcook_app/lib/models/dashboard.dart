class Dashboard {
  final int totalUsers;
  final int totalRecipes;

  Dashboard({required this.totalUsers, required this.totalRecipes});

  factory Dashboard.fromJson(Map<String, dynamic> json) {
    return Dashboard(
      totalUsers: json["total_users"],
      totalRecipes: json["total_recipes"],
    );
  }
}
