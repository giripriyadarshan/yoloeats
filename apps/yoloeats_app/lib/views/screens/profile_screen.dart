import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yoloeats_app/models/user_profile.dart';
import 'package:yoloeats_app/providers/user_profile_providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  // Controllers for text fields
  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;

  // Local state for dropdown/selections
  // Initialize with default or load from profile in initState/build
  RiskLevel? _selectedRiskLevel;
  List<String> _selectedAllergens = []; // Placeholder - load from profile
  List<String> _selectedDietaryPrefs = []; // Placeholder - load from profile

  // Flag to prevent overwriting controllers on every rebuild
  bool _isInitialized = false;
  // Store the loaded profile to compare against form changes
  UserProfile? _loadedProfile;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _emailController = TextEditingController();
    // Initial values will be set when the provider loads data
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // Helper to initialize/update form state from the loaded profile data
  void _updateFormState(UserProfile? profile) {
    // Only initialize once, or if the user context changes (e.g., different profile loaded)
    if (!_isInitialized || _loadedProfile?.userId != profile?.userId) {
      _loadedProfile = profile; // Store the loaded profile
      _usernameController.text = profile?.username ?? '';
      _emailController.text = profile?.email ?? '';
      _selectedRiskLevel = profile?.riskTolerance ?? RiskLevel.medium; // Default if null
      _selectedAllergens = List<String>.from(profile?.allergens ?? []); // Copy list
      _selectedDietaryPrefs = List<String>.from(profile?.dietaryPrefs ?? []); // Copy list
      if (profile != null) {
        _isInitialized = true; // Mark as initialized after first load with data
      }
      // Use setState if needed outside initial build, but here it happens during build
      // WidgetsBinding.instance.addPostFrameCallback((_) {
      //   if (mounted) setState(() {});
      // });
    }
  }

  void _saveProfile() {
    if (_loadedProfile == null) {
      // Or handle creating a new profile if that's intended
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No profile loaded to update.')),
      );
      return;
    }

    // Create updated profile from form state
    // Use copyWith on the _loadedProfile to preserve fields not edited (like userId)
    final updatedProfile = _loadedProfile!.copyWith(
      username: _usernameController.text,
      email: _emailController.text,
      riskTolerance: _selectedRiskLevel,
      allergens: _selectedAllergens, // Use current local state
      dietaryPrefs: _selectedDietaryPrefs, // Use current local state
    );

    // Call the notifier method to save (which includes optimistic update)
    ref.read(userProfileProvider.notifier).saveProfile(updatedProfile).then((_) {
      // Check if the state after save is an error or not
      // Note: .state might still be the optimistic state here.
      // A better approach might involve the notifier exposing a separate save status/error.
      final currentState = ref.read(userProfileProvider);
      if (currentState is AsyncError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error saving profile: ${currentState.error}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved locally!')),
        );
      }
    }).catchError((e, s) {
      // Catch potential errors not handled by the AsyncValue state directly
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save profile: $e')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final userProfileAsync = ref.watch(userProfileProvider);

    // Update form controllers/state when async value has data
    // This ensures the form reflects the loaded state
    if (userProfileAsync is AsyncData<UserProfile?>) {
      _updateFormState(userProfileAsync.value);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(userProfileProvider.notifier).refreshProfile(),
            tooltip: 'Refresh Profile',
          ),
        ],
      ),
      body: userProfileAsync.when(
        // --- Loading State ---
        loading: () => const Center(child: CircularProgressIndicator()),
        // --- Error State ---
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Error loading profile: $err'),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () => ref.read(userProfileProvider.notifier).refreshProfile(),
                  child: const Text('Retry'),
                )
              ],
            ),
          ),
        ),
        // --- Data State ---
        data: (profile) {
          // Build the form using the (potentially null) profile data
          // _updateFormState has already been called above to set controllers/local state
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('User ID: ${profile?.userId ?? "Not set"}'), // Display ID if available
                const SizedBox(height: 16),

                // --- Username ---
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}), // Trigger rebuild to enable/disable save potentially
                ),
                const SizedBox(height: 16),

                // --- Email ---
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 24),

                // --- Risk Tolerance ---
                const Text('Allergy Risk Tolerance:', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButtonFormField<RiskLevel>(
                  value: _selectedRiskLevel,
                  items: RiskLevel.values.map((level) {
                    return DropdownMenuItem(
                      value: level,
                      child: Text(level.toString().split('.').last), // Simple display name
                    );
                  }).toList(),
                  onChanged: (RiskLevel? newValue) {
                    setState(() {
                      _selectedRiskLevel = newValue;
                    });
                  },
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),

                // --- Allergens ---
                const Text('Allergens:', style: TextStyle(fontWeight: FontWeight.bold)),
                // TODO: Replace with multi-selection widget (e.g., Chips, Checkboxes)
                //       Needs a predefined list of possible allergens.
                Text('Selected: ${_selectedAllergens.join(", ")} (Widget TODO)'),
                // Example Chip implementation (requires a list of available allergens)
                // Wrap(
                //   spacing: 8.0,
                //   children: availableAllergens.map((allergen) => ChoiceChip(
                //     label: Text(allergen),
                //     selected: _selectedAllergens.contains(allergen),
                //     onSelected: (selected) {
                //       setState(() {
                //         if (selected) {
                //           _selectedAllergens.add(allergen);
                //         } else {
                //           _selectedAllergens.remove(allergen);
                //         }
                //       });
                //     },
                //   )).toList(),
                // ),
                const SizedBox(height: 24),

                // --- Dietary Preferences ---
                const Text('Dietary Preferences:', style: TextStyle(fontWeight: FontWeight.bold)),
                // TODO: Replace with multi-selection widget
                Text('Selected: ${_selectedDietaryPrefs.join(", ")} (Widget TODO)'),
                const SizedBox(height: 32),

                // --- Save Button ---
                ElevatedButton(
                  onPressed: _isInitialized ? _saveProfile : null, // Enable only when loaded
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Save Profile'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}