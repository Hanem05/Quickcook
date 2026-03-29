import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static Future<bool> get isOnline async {
    final r = await Connectivity().checkConnectivity();
    if (r.isEmpty) return true;
    return !r.contains(ConnectivityResult.none);
  }
}
