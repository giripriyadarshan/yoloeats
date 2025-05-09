import 'package:flutter/material.dart';

class PlaceholderScreen extends StatelessWidget {
  final String title;
  final IconData iconData;

  const PlaceholderScreen({
    required this.title,
    this.iconData = Icons.construction,
    super.key
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(iconData, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '$title Screen',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.grey[600]),
            ),
            const Text('(Coming Soon)', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}