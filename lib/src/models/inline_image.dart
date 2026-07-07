class InlineImage {
  final String id;
  final String token;
  final String imageUrl;

  const InlineImage({
    required this.id,
    required this.token,
    required this.imageUrl,
  });

  factory InlineImage.fromRow(
    Map<String, dynamic> row,
    String Function(String) urlBuilder,
  ) {
    final storagePath = row['storage_path']?.toString() ?? '';
    return InlineImage(
      id: row['id'].toString(),
      token: row['token']?.toString() ?? '',
      imageUrl: storagePath.isEmpty ? '' : urlBuilder(storagePath),
    );
  }

  String get inlineTag => '[img:$token]';
}
