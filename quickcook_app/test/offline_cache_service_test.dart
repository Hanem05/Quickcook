import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quickcook_app/services/offline_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves and loads recipe detail offline json', () async {
    await OfflineCacheService.saveRecipeDetailJson(42, '{"id":42}');
    final loaded = await OfflineCacheService.loadRecipeDetailJson(42);
    expect(loaded, '{"id":42}');
  });

  test('saves and loads collections offline json', () async {
    await OfflineCacheService.saveCollectionsJson('[{"id":1,"name":"Dinner"}]');
    final loaded = await OfflineCacheService.loadCollectionsJson();
    expect(loaded, '[{"id":1,"name":"Dinner"}]');
  });

  test('saves and loads collection detail offline json', () async {
    await OfflineCacheService.saveCollectionDetailJson(7, '{"id":7,"recipes":[]}');
    final loaded = await OfflineCacheService.loadCollectionDetailJson(7);
    expect(loaded, '{"id":7,"recipes":[]}');
  });
}
