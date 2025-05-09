import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/scanner_screen.dart';
import 'screens/search_screen.dart';
import 'screens/profile_screen.dart';
import 'widgets/placeholder_screen.dart';

import '../providers/ml_providers.dart';
import '../providers/user_profile_providers.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _selectedIndex = 2;
  bool _isLoadingServices = true;
  String _loadingMessage = "Initializing...";

  static const List<Widget> _widgetOptions = <Widget>[
    ScannerScreen(), // Index 0
    SearchScreen(),
    ProfileScreen(),
    PlaceholderScreen(title: 'Lists', iconData: Icons.list_alt),
  ];

  @override
  void initState() {
    super.initState();
    print("MainShell: initState - Initializing services...");
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeServices();
    });
  }

  Future<void> _initializeServices() async {
    if (!mounted) return;

    setState(() {
      _isLoadingServices = true;
      _loadingMessage = "Loading ML Model...";
    });

    try {
      print("MainShell: Pre-loading TFLite model...");
      await ref.read(tfliteServiceProvider).loadModel();
      print("MainShell: TFLite model loaded.");
      if (!mounted) return;
      setState(() { _loadingMessage = "Loading User Profile..."; });

      print("MainShell: Pre-loading user profile...");
      await ref.read(userProfileProvider.notifier).refreshProfile();
      print("MainShell: User profile refresh triggered.");
      if (!mounted) return;
      setState(() { _loadingMessage = "Loading Allergens..."; });


      print("MainShell: Pre-triggering allergens fetch...");
      ref.read(allergensProvider);
      print("MainShell: Allergens fetch triggered.");


      print("MainShell: Service initialization complete.");
      if (mounted) {
        setState(() { _isLoadingServices = false; });
      }

    } catch (e, stackTrace) {
      print("!!!! MainShell: FAILED TO INITIALIZE SERVICES: $e !!!!");
      print("!!!! Stack Trace: $stackTrace !!!!");
      if (mounted) {
        setState(() {
          _isLoadingServices = false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error initializing core services: $e'),
              duration: const Duration(seconds: 5),
              backgroundColor: Colors.red,
            ),
          );
        });
      }
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: _widgetOptions,
          ),
          if (_isLoadingServices)
            Container(
              color: Colors.black.withOpacity(0.6),
              child: Center(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 16),
                        Text(_loadingMessage, style: const TextStyle(color: Colors.white, fontSize: 16)),
                      ]
                  )
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt_outlined),
            activeIcon: Icon(Icons.camera_alt),
            label: 'Scanner',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart_outlined),
            activeIcon: Icon(Icons.shopping_cart),
            label: 'Lists',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey[600],
        onTap: _onItemTapped,
        showUnselectedLabels: true,
      ),
    );
  }
}