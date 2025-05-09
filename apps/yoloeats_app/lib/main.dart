import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/allergen_info.dart';
import 'models/user_profile.dart';
import 'models/product_info.dart';
import 'models/product.dart';
import 'views/main_shell.dart';
import 'providers/auth_providers.dart';

const String userProfileBoxName = 'userProfileBox';
const String allergenListBoxName = 'allergenListBox';
const String productCacheBoxName = 'productCacheBox';
const String productDetailBoxName = 'productDetailBox';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print("Flutter Binding Initialized.");

  try {
    print("Initializing Hive...");
    final appDocumentDir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(appDocumentDir.path);
    print("Hive initialized at ${appDocumentDir.path}");

    print("Registering Hive adapters...");
    if (!Hive.isAdapterRegistered(RiskLevelAdapter().typeId)) Hive.registerAdapter(RiskLevelAdapter());
    if (!Hive.isAdapterRegistered(UserProfileAdapter().typeId)) Hive.registerAdapter(UserProfileAdapter());
    if (!Hive.isAdapterRegistered(AllergenInfoAdapter().typeId)) Hive.registerAdapter(AllergenInfoAdapter());
    if (!Hive.isAdapterRegistered(ProductInfoAdapter().typeId)) Hive.registerAdapter(ProductInfoAdapter());
    if (!Hive.isAdapterRegistered(ProductAdapter().typeId)) Hive.registerAdapter(ProductAdapter());
    print("Hive adapters registered.");

    print("Opening essential Hive boxes...");
    await Hive.openBox<UserProfile>(userProfileBoxName);
    await Hive.openBox<List>(allergenListBoxName);
    await Hive.openBox<ProductInfo>(productCacheBoxName);
    await Hive.openBox<Product>(productDetailBoxName);
    print("Essential Hive boxes opened.");

  } catch (e, stackTrace) {
    print("!!!! HIVE INITIALIZATION FAILED: $e !!!!");
    print("!!!! Stack Trace: $stackTrace !!!!");
  }

  print("Creating ProviderContainer...");
  final container = ProviderContainer();

  try {
    await initializeCurrentUserId(container);
  } catch (e, stackTrace) {
    print("!!!! FAILED TO INITIALIZE USER ID: $e !!!!");
    print("!!!! Stack Trace: $stackTrace !!!!");
  }

  print("Running app...");
  runApp(
      UncontrolledProviderScope(
        container: container,
        child: const MyApp(),
      )
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
      debugShowCheckedModeBanner: false,
      home: const MainShell(),
    );
  }
}