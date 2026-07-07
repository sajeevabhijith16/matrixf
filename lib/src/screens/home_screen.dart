import 'package:flutter/material.dart';
import '../models/models.dart';
import '../app.dart'; // For MatrixScope
import '../widgets/shared_widgets.dart';

// ─── Home Screen ─────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Course>> future;
  late Future<Profile?> profileFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = MatrixScope.of(context).api;
    future = api.listCourses();
    profileFuture = api.isSignedIn
        ? api.getProfile()
        : Future.value(null);
  }

  @override
  Widget build(BuildContext context) {
    final scope = MatrixScope.of(context);
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          future = scope.api.listCourses();
          profileFuture = scope.api.isSignedIn
              ? scope.api.getProfile()
              : Future.value(null);
        });
        await Future.wait([future, profileFuture]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 56, 16, 24),
        children: [
          const BrandHeader(),
          const SizedBox(height: 12),
          FutureBuilder<Profile?>(
            future: profileFuture,
            builder: (context, snapshot) {
              final profile = snapshot.data;
              final greeting = profile != null
                  ? 'Hi, ${profile.fullName.split(' ').first}'
                  : 'Welcome';
              return Text(
                greeting,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.black.withValues(alpha: .75),
                    ),
              );
            },
          ),
          const SizedBox(height: 34),
          Text(
            'Read deeper.\nLearn slower.',
            ...