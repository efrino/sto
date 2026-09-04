import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/config/app_config.dart';
import 'core/di/dependencies.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_page.dart';
import 'features/home/home_page.dart';
import 'features/prepare/prepare_page.dart';
import 'features/preview/print_preview_page.dart';
import 'features/cancel/cancel_tag_page.dart';
import 'features/chat/chat_page.dart';
import 'features/history/riwayat_page.dart';
import 'features/tagok/tag_ok_page.dart';
import 'features/scan/scan_count_page.dart';
import 'features/search/part_search_page.dart';
import 'features/settings/admin_devices_page.dart';
import 'features/settings/admin_events_page.dart';
import 'features/settings/admin_users_page.dart';
import 'features/settings/printer_setup_page.dart';
import 'features/settings/settings_page.dart';
import 'features/splash/splash_page.dart';
import 'state/admin_provider.dart';
import 'state/cancel_provider.dart';
import 'state/count_provider.dart';
import 'state/device_provider.dart';
import 'state/prepare_provider.dart';
import 'state/chat_provider.dart';
import 'state/print_history_provider.dart';
import 'state/printer_provider.dart';
import 'state/tag_ok_provider.dart';
import 'state/session_provider.dart';
import 'state/settings_provider.dart';

class AppRoutes {
  AppRoutes._();

  static const splash = '/';
  static const login = '/login';
  static const home = '/home';
  static const search = '/search';
  static const prepare = '/prepare';
  static const preview = '/preview';
  static const scan = '/scan';
  static const cancel = '/cancel';
  static const history = '/history';
  static const siapkanTagOk = '/tag-ok/siapkan';
  static const scanTagOk = '/tag-ok/scan';
  static const batalTagOk = '/tag-ok/batal';
  static const chat = '/chat';
  static const settings = '/settings';
  static const printerSetup = '/settings/printer';
  static const adminEvents = '/settings/events';
  static const adminUsers = '/settings/users';
  static const adminDevices = '/settings/devices';
}

class StoPrepApp extends StatelessWidget {
  const StoPrepApp({super.key, required this.deps});

  final AppDependencies deps;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDependencies>.value(value: deps),
        ChangeNotifierProvider(
          create: (_) => SessionProvider(deps.authRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => ChatProvider(deps.api),
        ),
        ChangeNotifierProvider(
          create: (_) => PrintHistoryProvider(api: deps.api),
        ),
        ChangeNotifierProvider(
          create: (_) => TagOkProvider(deps.api),
        ),
        ChangeNotifierProvider(
          create: (_) => PrinterProvider(
            service: deps.printerService,
            prefs: deps.prefs,
            api: deps.api,
            cadangan: deps.printerFallback,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => PrepareProvider(
            partRepository: deps.partRepository,
            tagRepository: deps.tagRepository,
            syncRepository: deps.syncRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => AdminProvider(deps.adminRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => DeviceProvider(deps.deviceRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => CountProvider(
            countRepository: deps.countRepository,
            syncRepository: deps.syncRepository,
            tagRepository: deps.tagRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              CancelProvider(deps.cancelRepository, deps.syncRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(
            prefs: deps.prefs,
            api: deps.api,
            partRepository: deps.partRepository,
            database: deps.database,
            sound: deps.sound,
            demoSeeder: deps.demoSeeder,
          ),
        ),
      ],
      child: MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        initialRoute: AppRoutes.splash,
        routes: {
          AppRoutes.splash: (_) => const SplashPage(),
          AppRoutes.login: (_) => const LoginPage(),
          AppRoutes.home: (_) => const HomePage(),
          AppRoutes.search: (_) => const PartSearchPage(),
          AppRoutes.prepare: (_) => const PreparePage(),
          AppRoutes.preview: (_) => const PrintPreviewPage(),
          AppRoutes.scan: (_) => const ScanCountPage(),
          AppRoutes.cancel: (_) => const CancelTagPage(),
          AppRoutes.history: (_) => const RiwayatPage(),
          AppRoutes.siapkanTagOk: (_) =>
              const TagOkPage(mode: TagOkMode.siapkan),
          AppRoutes.scanTagOk: (_) => const TagOkPage(mode: TagOkMode.hitung),
          AppRoutes.batalTagOk: (_) => const TagOkPage(mode: TagOkMode.batal),
          AppRoutes.chat: (_) => const ChatPage(),
          AppRoutes.settings: (_) => const SettingsPage(),
          AppRoutes.printerSetup: (_) => const PrinterSetupPage(),
          AppRoutes.adminEvents: (_) => const AdminEventsPage(),
          AppRoutes.adminUsers: (_) => const AdminUsersPage(),
          AppRoutes.adminDevices: (_) => const AdminDevicesPage(),
        },
      ),
    );
  }
}
