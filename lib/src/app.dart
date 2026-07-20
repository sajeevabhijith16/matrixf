import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'ai/ai_models.dart';
import 'api.dart';
import 'models/models.dart';
import 'screens/home_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/library_screen.dart';
import 'screens/support_screen.dart';
import 'screens/profile_screen.dart';
import 'widgets/ai_chat_overlay.dart';

// ─── App Shell ───────────────────────────────────────────────────────────────

class MatrixApp extends StatefulWidget {
  const MatrixApp({super.key});

  @override
  State<MatrixApp> createState() => _MatrixAppState();
}

class _MatrixAppState extends State<MatrixApp> with WidgetsBindingObserver {
  final MatrixApi api = matrixApi;
  int tab = 0;
  Profile? profile;
  bool _initialized = false;
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initGoogleSignIn();
    _initApi();
    _initDeepLinks();
  }

  Future<void> _initGoogleSignIn() async {
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId:
            '671119999667-2t4gb0s6avs6k6mq77lop28km6mbda2k.apps.googleusercontent.com',
      );
    } catch (e) {
      debugPrint('GoogleSignIn init failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  /// Catches sign-ins that completed via an external browser/Custom Tab
  /// (e.g. Google OAuth) while the app was backgrounded — this is a
  /// resilience safety net in addition to the direct handleOAuthCallback
  /// path in _googleSignIn, covering cases where the app process was
  /// suspended/recreated during a prolonged background period.
  Future<void> _onAppResumed() async {
    if (!api.isSignedIn || profile != null) return;
    try {
      await refreshProfile();
    } catch (e) {
      debugPrint('Resume profile refresh failed: $e');
    }
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
    WidgetsBinding.instance.removeObserver(this);
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

  AiCourse? pendingAiCourse;

  void requestAiSignIn(AiCourse course) {
    setState(() {
      pendingAiCourse = course;
      tab = 4; // Profile tab
    });
  }

  void clearPendingAiCourse() {
    setState(() => pendingAiCourse = null);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MatrixScope(
      api: api,
      profile: profile,
      refreshProfile: refreshProfile,
      setTab: setTab,
      pendingAiCourse: pendingAiCourse,
      requestAiSignIn: requestAiSignIn,
      clearPendingAiCourse: clearPendingAiCourse,
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
    required this.pendingAiCourse,
    required this.requestAiSignIn,
    required this.clearPendingAiCourse,
    required super.child,
  });
  final MatrixApi api;
  final Profile? profile;
  final Future<void> Function() refreshProfile;
  final void Function(int tab) setTab;

  // AI Tutor sign-in gating: when a guest picks a course, we stash it here,
  // switch to the Profile tab, and MatrixShell reopens the chat sheet with
  // this course once sign-in succeeds.
  final AiCourse? pendingAiCourse;
  final void Function(AiCourse course) requestAiSignIn;
  final VoidCallback clearPendingAiCourse;

  static MatrixScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MatrixScope>();
    assert(scope != null, 'MatrixScope missing');
    return scope!;
  }

  @override
  bool updateShouldNotify(MatrixScope oldWidget) =>
      profile != oldWidget.profile || api.session != oldWidget.api.session;
}

class MatrixShell extends StatefulWidget {
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
  State<MatrixShell> createState() => _MatrixShellState();
}

class _MatrixShellState extends State<MatrixShell> {
  @override
  void didUpdateWidget(covariant MatrixShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final justSignedIn = oldWidget.profile == null && widget.profile != null;
    if (justSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeReopenAiChat());
    }
  }

  void _maybeReopenAiChat() {
    if (!mounted) return;
    final scope = MatrixScope.of(context);
    final course = scope.pendingAiCourse;
    if (course == null) return;
    scope.clearPendingAiCourse();
    openAiChatSheet(context, initialCourse: course);
  }

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
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        label: 'Home',
      ),
      const NavigationDestination(icon: Icon(Icons.search), label: 'Catalog'),
      const NavigationDestination(
        icon: Icon(Icons.menu_book_outlined),
        label: 'Library',
      ),
      const NavigationDestination(
        icon: Icon(Icons.support_agent),
        label: 'Support',
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline),
        label: 'Profile',
      ),
    ];
    final safeTab = widget.tab >= pages.length ? 0 : widget.tab;
    return Scaffold(
      body: AiChatOverlay(child: pages[safeTab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeTab,
        onDestinationSelected: widget.onTabChanged,
        destinations: items,
      ),
    );
  }
}
