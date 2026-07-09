import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/models.dart';
import '../app.dart';
import 'banner_edit_screen.dart';

class BannersAdminScreen extends StatefulWidget {
  const BannersAdminScreen({super.key});

  @override
  State<BannersAdminScreen> createState() => _BannersAdminScreenState();
}

class _BannersAdminScreenState extends State<BannersAdminScreen> {
  late Future<List<AppBanner>> future;

  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  void _load() {
    future = MatrixScope.of(context).api.adminListBanners();
  }

  Future<void> _openEditor([AppBanner? banner]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BannerEditScreen(existing: banner)),
    );
    if (changed == true) setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Banners')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add banner'),
      ),
      body: FutureBuilder<List<AppBanner>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load banners: ${snapshot.error}'),
            );
          }
          final banners = snapshot.data ?? [];
          if (banners.isEmpty) {
            return const Center(
              child: Text('No banners yet. Tap "Add banner" to create one.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: banners.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final banner = banners[index];
              return _BannerRow(
                banner: banner,
                onTap: () => _openEditor(banner),
              );
            },
          );
        },
      ),
    );
  }
}

class _BannerRow extends StatelessWidget {
  const _BannerRow({required this.banner, required this.onTap});
  final AppBanner banner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .03),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 72,
                  height: 48,
                  child: CachedNetworkImage(
                    imageUrl: banner.imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) =>
                        const Icon(Icons.image_not_supported_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      banner.redirectCourseSlug != null
                          ? 'Links to: ${banner.redirectCourseSlug}'
                          : 'Decorative',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      'Order ${banner.displayOrder}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black.withValues(alpha: .5),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (banner.isActive ? Colors.green : Colors.grey)
                      .withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  banner.isActive ? 'Active' : 'Hidden',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: banner.isActive
                        ? Colors.green[800]
                        : Colors.grey[700],
                  ),
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
