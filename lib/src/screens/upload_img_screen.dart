import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../api.dart';
import '../models/inline_image.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final ImagePicker _picker = ImagePicker();
  final MatrixApi _api = matrixApi;

  File? _selectedImage;
  bool _loading = true;
  bool _uploading = false;

  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  List<InlineImage> _images = [];

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    setState(() => _loading = true);
    try {
      final rows = await _api.adminListImageTokens();
      setState(() {
        _images =
            rows.map((r) => InlineImage.fromRow(r, _api.publicImageUrl)).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to load: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<InlineImage> get _filteredImages {
    final query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) {
      return _images;
    }

    return _images.where((image) {
      return image.token.toLowerCase().contains(query);
    }).toList();
  }

  bool _isValidToken(String token) {
    return RegExp(r'^[a-z0-9_]+$').hasMatch(token);
  }

  bool _tokenExists(String token) {
    return _images.any(
      (image) => image.token.toLowerCase() == token.toLowerCase(),
    );
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );

    if (image == null) return;

    setState(() {
      _selectedImage = File(image.path);
    });
  }

  Future<void> _upload() async {
    final token = _tokenController.text.trim();

    if (_selectedImage == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please select an image.")));
      return;
    }

    if (token.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please enter a token.")));
      return;
    }

    if (!_isValidToken(token)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Only lowercase letters, numbers and underscores are allowed.",
          ),
        ),
      );
      return;
    }

    if (_tokenExists(token)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Token '$token' already exists.")));
      return;
    }

    setState(() => _uploading = true);
    try {
      await _api.adminUploadImageToken(token, _selectedImage!);
      setState(() {
        _selectedImage = null;
        _tokenController.clear();
      });
      await _loadImages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("[img:$token] registered successfully.")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteImage(InlineImage image) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Token"),
        content: Text("Delete [img:${image.token}]?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Delete")),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final storagePath = image.imageUrl.split('/course-images/').last;
      await _api.adminDeleteImageToken(id: image.id, storagePath: storagePath);
      await _loadImages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = _tokenController.text.trim();

    return Scaffold(
      appBar: AppBar(title: const Text("Image Tokens")),
      body: _loading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Select Image",
              style: Theme.of(context).textTheme.titleMedium,
            ),

            const SizedBox(height: 12),

            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _selectedImage == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image_outlined, size: 48),
                          SizedBox(height: 12),
                          Text("Tap to select image"),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(_selectedImage!, fit: BoxFit.cover),
                      ),
              ),
            ),

            const SizedBox(height: 24),

            Text("Image Token", style: Theme.of(context).textTheme.titleMedium),

            const SizedBox(height: 8),

            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "amplifier",
              ),
              onChanged: (_) {
                setState(() {});
              },
            ),

            const SizedBox(height: 20),

            Text(
              "Inline Usage",
              style: Theme.of(context).textTheme.titleMedium,
            ),

            const SizedBox(height: 8),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                token.isEmpty ? "[img:token]" : "[img:$token]",
                style: const TextStyle(
                  fontFamily: "monospace",
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image),
                    label: const Text("Select Image"),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: FilledButton.icon(
                    onPressed: _uploading ? null : _upload,
                    icon: _uploading 
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) 
                        : const Icon(Icons.cloud_upload),
                    label: Text(_uploading ? "Uploading..." : "Upload"),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            Text(
              "Search Token",
              style: Theme.of(context).textTheme.titleMedium,
            ),

            const SizedBox(height: 8),

            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: "Search...",
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 24),

            Text(
              "Registered Tokens",
              style: Theme.of(context).textTheme.titleMedium,
            ),

            const SizedBox(height: 12),

            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _filteredImages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final image = _filteredImages[index];

                return Card(
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: image.imageUrl.isNotEmpty
                          ? Image.network(
                              image.imageUrl,
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
                            )
                          : Container(
                              width: 50,
                              height: 50,
                              color: Colors.grey.shade300,
                              child: const Icon(Icons.image),
                            ),
                    ),
                    title: Text(image.token),
                    subtitle: SelectableText(image.inlineTag),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: "Preview",
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  "Preview ${image.token} (backend later)",
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.visibility_outlined),
                        ),
                        IconButton(
                          tooltip: "Delete",
                          onPressed: () => _deleteImage(image),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
