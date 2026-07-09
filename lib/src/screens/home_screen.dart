import 'package:flutter/material.dart';
import '../models/models.dart';
import '../app.dart'; // For MatrixScope
import '../widgets/shared_widgets.dart';
import '../widgets/banner_carousel.dart';

// ─── Home Screen ─────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Course>> coursesFuture;
  late Future<Profile?> profileFuture;
  late Future<List<AppBanner>> bannersFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  void _load() {
    final api = MatrixScope.of(context).api;
    coursesFuture = api.listCourses();
    bannersFuture = api.listBanners();
    profileFuture = api.isSignedIn ? api.getProfile() : Future.value(null);
  }

  @override
  Widget build(BuildContext context) {
    final scope = MatrixScope.of(context);
    return RefreshIndicator(
      onRefresh: () async {
        setState(_load);
        await Future.wait([coursesFuture, bannersFuture, profileFuture]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 56, 16, 24),
        children: [
          const BrandHeader(),
          const SizedBox(height: 12),
          FutureBuilder<Profile?>(
            future: profileFuture,
            builder: (context, snapshot) {
              return Text(
                _greetingFor(snapshot.data),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withValues(alpha: .75),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          FutureBuilder<List<AppBanner>>(
            future: bannersFuture,
            builder: (context, snapshot) {
              // Stay silent while loading / on error — this is a marketing
              // strip, not core content, so it shouldn't jank the page.
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox.shrink();
              }
              final banners = snapshot.data ?? [];
              return BannerCarousel(banners: banners);
            },
          ),
          const SizedBox(height: 22),
          Text(
            'Read deeper.\nLearn slower.',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.02,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Matrix is a focused mobile shelf for premium text modules. Browse courses, unlock only what you need, and read inside a quiet text-first reader.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.black.withValues(alpha: .62),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () => scope.setTab(1),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Browse catalog'),
          ),
          const SizedBox(height: 34),
          const SectionTitle(title: 'Browse by program'),
          const SizedBox(height: 12),
          FutureBuilder<List<Course>>(
            future: coursesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingList();
              }
              if (snapshot.hasError) return ErrorBox(snapshot.error.toString());
              final courses = snapshot.data ?? [];
              if (courses.isEmpty) {
                return const EmptyBox('No courses published yet.');
              }
              return ProgramGrid(courses: courses);
            },
          ),
          const SizedBox(height: 18),
          const TrustTile(
            icon: Icons.text_snippet_outlined,
            title: 'Text-first modules',
            body: 'Structured lessons and Q&A in a quiet reader.',
          ),
          const TrustTile(
            icon: Icons.lock_outline,
            title: 'Member access',
            body:
                'Open free previews, member-free lessons, and modules you own.',
          ),
        ],
      ),
    );
  }

  String _greetingFor(Profile? profile) {
    if (profile == null) return 'Welcome';
    final name = profile.fullName?.trim() ?? '';
    if (name.isEmpty) return 'Hi there';
    return 'Hi, ${name.split(' ').first}';
  }
}
