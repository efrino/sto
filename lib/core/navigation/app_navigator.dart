import 'package:flutter/material.dart';

/// Akses navigator global untuk aksi di luar BuildContext (mis. auto-logout saat sesi berakhir).
class AppNavigator {
  AppNavigator._();

  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
}
