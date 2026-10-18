import 'package:flutter/material.dart';

class NearbyMediaPreview extends StatelessWidget {
  const NearbyMediaPreview({
    super.key,
    required this.path,
    required this.type,
    required this.name,
  });
  final String path, type, name;
  @override
  Widget build(BuildContext context) => Text(name);
}
