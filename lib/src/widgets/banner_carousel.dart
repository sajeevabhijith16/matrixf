import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/models.dart';
import 'shared_widgets.dart'; // for openCourse(context, slug)

class BannerCarousel extends StatelessWidget {
  const BannerCarousel({super.key, required this.banners});

  final List<AppBanner> banners;

  @override
  Widget build(BuildContext context) {
    if (banners.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 140,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.96),
        itemCount: banners.length,
        itemBuilder: (context, index) {
          final banner = banners[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _BannerCard(banner: banner),
          );
        },
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.banner});

  final AppBanner banner;

  @override
  Widget build(BuildContext context) {
    final tappable = banner.redirectCourseSlug != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: Colors.black.withValues(alpha: .04),
        child: InkWell(
          onTap: tappable
              ? () => openCourse(context, banner.redirectCourseSlug!)
              : null,
          child: CachedNetworkImage(
            imageUrl: banner.imageUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            placeholder: (context, url) => const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: Colors.black.withValues(alpha: .05),
              alignment: Alignment.center,
              child: const Icon(Icons.image_not_supported_outlined),
            ),
          ),
        ),
      ),
    );
  }
}
