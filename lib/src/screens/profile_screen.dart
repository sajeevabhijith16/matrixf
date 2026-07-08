import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../app.dart'; // For MatrixScope
import '../widgets/shared_widgets.dart';
import '../api.dart';
import '../ai/gemini_embedding_api.dart';

import "admin_screen.dart";
// ─── Profile Screen ───────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool signUp = false;
  bool loading = false;
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = MatrixScope.of(context);
    final profile = scope.profile;
    if (scope.api.isSignedIn && profile != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 56, 16, 24),
        children: [
          const BrandHeader(),
          const SizedBox(height: 24),
          Text('Your account', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Matrix ID', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          profile.matrixId ?? '...',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: 'Copy Matrix ID',
                        onPressed: () {
                          if (profile.matrixId != null) {
                            Clipboard.setData(ClipboardData(text: profile.matrixId!));
                            showSnack(context, 'Matrix ID copied');
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  InfoRow('Name', profile.fullName ?? '-'),
                  InfoRow('Email', profile.email ?? '-'),
                  InfoRow('Role', profile.isAdmin ? 'Admin' : 'Learner'),
                  const SizedBox(height: 18),
                  if (profile.isAdmin) ...[
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const Scaffold(
                            body: AdminScreen(),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.shield_outlined),
                      label: const Text('Open admin console'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    onPressed: () {
                      scope.api.signOut();
                      scope.refreshProfile();
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () async {
                      final matrixApi = scope.api;
                      const testCourseId = '456dc0bd-1933-475b-b7e0-8fc22dc81477';

                      final modules = await matrixApi.listModulesByCourseId(testCourseId);
                      debugPrint('[AI-DEBUG] Modules: ${modules.length}');

                      final rows = await matrixApi.callMatchAiCache(
                        courseId: testCourseId,
                        embedding: List.filled(768, 0.1),
                        threshold: 0.5,
                      );
                      debugPrint('[AI-DEBUG] Match rows (expect 0): ${rows.length}');

                      await matrixApi.insertAiCache({
                        'course_id': 'test',
                        'question': 'debug question',
                        'answer': 'debug answer',
                        'embedding': List.filled(768, 0.1),
                      });
                      debugPrint('[AI-DEBUG] Insert done — check Supabase ai_qa_cache table');
                    },
                    child: const Text('[DEBUG] Test Module 5'),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () async {
                      final matrixApi = scope.api;
                      await matrixApi.patchAiCacheHitCount('1baa91bd-83a7-4b45-a2e3-5fde8c98b6e5');
                      debugPrint('[AI-DEBUG] Patch done — check hit_count in Supabase, expect 2');
                    },
                    child: const Text('[DEBUG] Test hit count patch'),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        final api = GeminiEmbeddingApi();
                        final vec = await api.embed('What is integration?');
                        debugPrint('[AI-DEBUG] Vector length: ${vec.length}');
                        debugPrint('[AI-DEBUG] First 5: ${vec.take(5).toList()}');
                      } catch (e) {
                        debugPrint('[AI-DEBUG] Error: $e');
                      }
                    },
                    child: const Text('[DEBUG] Test Embedding'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          FutureBuilder<List<Purchase>>(
            future: scope.api.getPurchases(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final purchases = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Purchase history', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (purchases.isEmpty)
                    const EmptyBox('No purchases yet.')
                  else
                    ...purchases.map((p) => Card(
                          child: ListTile(
                            title: Text(formatInr(p.amountInr)),
                            subtitle: Text('${p.status}  ${p.createdAt ?? ''}'),
                          ),
                        )),
                ],
              );
            },
          ),
        ],
      );
    }

    // ─── Sign-in / Sign-up form ───────────────────────────────────────────────
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 56, 16, 24),
      children: [
        const BrandHeader(),
        const SizedBox(height: 24),
        Text(
          signUp ? 'Join Matrix' : 'Sign in to Matrix',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 16),
        if (signUp) ...[
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: loading ? null : () => _submitAuth(context),
          child: Text(loading ? 'Please wait...' : signUp ? 'Create account' : 'Sign in'),
        ),
        const SizedBox(height: 10),
        // ─── Google OAuth button ────────────────────────────────────────────
        OutlinedButton.icon(
          icon: const Icon(Icons.account_circle_outlined),
          label: const Text('Continue with Google'),
          onPressed: loading ? null : () => _googleSignIn(context),
        ),
        TextButton(
          onPressed: () => setState(() => signUp = !signUp),
          child: Text(signUp ? 'Already have an account? Sign in' : 'New here? Create account'),
        ),
      ],
    );
  }

  Future<void> _submitAuth(BuildContext context) async {
    final scope = MatrixScope.of(context);
    setState(() => loading = true);
    try {
      if (signUp) {
        await scope.api.signUp(name.text.trim(), email.text.trim(), password.text);
        if (context.mounted) {
          showSnack(context, 'Check your email to confirm your account.');
          setState(() => signUp = false);
        }
      } else {
        await scope.api.signIn(email.text.trim(), password.text);
        await scope.refreshProfile();
      }
    } catch (error) {
      if (context.mounted) showSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _googleSignIn(BuildContext context) async {
    final scope = MatrixScope.of(context);
    final oauthUrl = scope.api.getGoogleOAuthUrl('matrixf://auth/callback');
    final uri = Uri.parse(oauthUrl);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        showSnack(context, 'Could not open browser. Please try again.');
      }
    } catch (e) {
      if (context.mounted) showSnack(context, 'Could not open browser for Google sign-in.');
    }
  }
}
