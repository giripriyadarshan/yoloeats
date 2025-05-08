import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/allergen_info.dart';
import 'models/user_profile.dart';
import 'models/product_info.dart';
import 'models/product.dart';
import 'views/main_shell.dart';

const String userProfileBoxName = 'userProfileBox';
const String allergenListBoxName = 'allergenListBox';
const String productCacheBoxName = 'productCacheBox';
const String productDetailBoxName = 'productDetailBox';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    print("Initializing Hive...");
    final appDocumentDir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(appDocumentDir.path);
    print("Hive initialized at ${appDocumentDir.path}");

    if (!Hive.isAdapterRegistered(RiskLevelAdapter().typeId)) {
      Hive.registerAdapter(RiskLevelAdapter());
    }
    if (!Hive.isAdapterRegistered(UserProfileAdapter().typeId)) {
      Hive.registerAdapter(UserProfileAdapter());
    }
    if (!Hive.isAdapterRegistered(AllergenInfoAdapter().typeId)) {
      Hive.registerAdapter(AllergenInfoAdapter());
    }
    if (!Hive.isAdapterRegistered(ProductInfoAdapter().typeId)) {
      Hive.registerAdapter(ProductInfoAdapter());
    }
    if (!Hive.isAdapterRegistered(ProductAdapter().typeId)) {
      Hive.registerAdapter(ProductAdapter());
    }
    print("Hive adapters registered.");

    print("Opening Hive boxes...");
    await Hive.openBox<UserProfile>(userProfileBoxName);
    await Hive.openBox<List>(allergenListBoxName);
    await Hive.openBox<ProductInfo>(productCacheBoxName);
    await Hive.openBox<Product>(productDetailBoxName);
    print("Hive boxes opened.");

  } catch (e) {
    print("!!!! HIVE INITIALIZATION FAILED: $e !!!!");
  }


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
        // bottomNavigationBarTheme: BottomNavigationBarThemeData(
        //   selectedItemColor: Colors.amber[800],
        //   unselectedItemColor: Colors.grey,
        // ),
      ),
      debugShowCheckedModeBanner: false,
      home: const MainShell(),
    );
  }
}