import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app.dart'; // For MatrixScope
import '../widgets/shared_widgets.dart';
// ─── Support Screen ───────────────────────────────────────────────────────────

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = MatrixScope.of(context).profile;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 56, 16, 24),
      children: [
        const BrandHeader(),
        const SizedBox(height: 24),
        Text("We're here to help", style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        const Text(
          'For refunds, access problems, or questions about a course, contact support@matrix.app and include your Matrix ID.',
          style: TextStyle(height: 1.5),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Matrix ID'),
            subtitle: SelectableText(profile?.matrixId ?? 'Sign in to view your Matrix ID'),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.mail_outline),
          label: const Text('Email support'),
          onPressed: () => launchUrl(Uri.parse('mailto:support@matrix.app')),
        ),
      ],
    );
  }
}
