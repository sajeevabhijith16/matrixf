import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'models/models.dart';
import 'screens/home_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/library_screen.dart';
import 'screens/support_screen.dart';
import 'screens/profile_screen.dart';

// ─── App Shell ───────────────────────────────────────────────────────────────

class MatrixApp extends StatefulWidget {
  const MatrixApp({super.key});

  @override
  State<MatrixApp> createState() => _MatrixAppState();
}

class _MatrixAppState extends State<MatrixApp> {
  final MatrixApi api = matrixApi;
  int tab = 0;
  Profile? profile;
  bool _initialized = false;
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _initApi();
    _initDeepLinks();
  }

  void _initDeepLinks() {
    final appLinks = AppLinks();
    // Handle deep link that launched the app cold (if any)
    appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleLink(uri);
    });
    // Handle deep links while the app is already running
    _linkSub = appLinks.uriLinkStream.listen(_handleLink);
  }

  Future<void> _handleLink(Uri uri) async {
    if (uri.scheme == 'matrixf' && uri.host == 'auth') {
      final ok = await api.handleOAuthCallback(uri);
      if (ok) await refreshProfile();
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  Future<void> _initApi() async {
    await api.init();
    if (api.isSignedIn) {
      try {
        await refreshProfile();
      } catch (e) {
        // Access token may be expired — try refreshing silently
        debugPrint('Profile load failed: $e — attempting token refresh');
        final refreshed = await api.refreshSession();
        if (refreshed) {
          try {
            await refreshProfile();
          } catch (e2) {
            debugPrint('Profile load after refresh failed: $e2 — signing out');
            api.signOut();
          }
        } else {
          // Refresh token also invalid — clear session and show as signed-out
          debugPrint('Refresh failed — clearing session');
          api.signOut();
        }
      }
    }
    if (mounted) {
      setState(() => _initialized = true);
    }
  }


  Future<void> refreshProfile() async {
    if (!api.isSignedIn) {
      setState(() => profile = null);
      return;
    }
    final next = await api.getProfile();
    setState(() => profile = next);
  }

  void setTab(int value) => setState(() => tab = value);

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MatrixScope(
      api: api,
      profile: profile,
      refreshProfile: refreshProfile,
      setTab: setTab,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Matrix',
        theme: _theme(),
        home: MatrixShell(tab: tab, onTabChanged: setTab, profile: profile),
      ),
    );
  }
}

ThemeData _theme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff18664b),
    brightness: Brightness.light,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xfffbfaf8),
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: Color(0xfffbfaf8),
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.black.withValues(alpha: .08)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

class MatrixScope extends InheritedWidget {
  const MatrixScope({
    super.key,
    required this.api,
    required this.profile,
    required this.refreshProfile,
    required this.setTab,
    required super.child,
  });

  final MatrixApi api;
  final Profile? profile;
  final Future<void> Function() refreshProfile;
  final void Function(int tab) setTab;

  static MatrixScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MatrixScope>();
    assert(scope != null, 'MatrixScope missing');
    return scope!;
  }

  @override
  bool updateShouldNotify(MatrixScope oldWidget) =>
      profile != oldWidget.profile || api.session != oldWidget.api.session;
}

class MatrixShell extends StatelessWidget {
  const MatrixShell({
    super.key,
    required this.tab,
    required this.onTabChanged,
    required this.profile,
  });

  final int tab;
  final ValueChanged<int> onTabChanged;
  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomeScreen(),
      const CatalogScreen(),
      const LibraryScreen(),
      const SupportScreen(),
      const ProfileScreen(),
    ];
    final items = [
      const NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
      const NavigationDestination(icon: Icon(Icons.search), label: 'Catalog'),
      const NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: 'Library'),
      const NavigationDestination(icon: Icon(Icons.support_agent), label: 'Support'),
      const NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
    ];
    final safeTab = tab >= pages.length ? 0 : tab;
    return Scaffold(
      body: pages[safeTab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeTab,
        onDestinationSelected: onTabChanged,
        destinations: items,
      ),
    );
  }
}
