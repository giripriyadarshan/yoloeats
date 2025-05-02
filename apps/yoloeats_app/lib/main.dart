import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/user_profile.dart';

const String userProfileBoxName = 'userProfileBox';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appDocumentDir = await getApplicationDocumentsDirectory();

  await Hive.initFlutter(appDocumentDir.path);

  Hive.registerAdapter(RiskLevelAdapter());
  Hive.registerAdapter(UserProfileAdapter());

  await Hive.openBox<UserProfile>(userProfileBoxName);

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yoloeats Allergy App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // TODO: Replace with your actual home screen/widget
      home: const Scaffold(
        body: Center(
          child: Text('App Initialized with Hive and Riverpod!'),
        ),
      ),
    );
  }
}