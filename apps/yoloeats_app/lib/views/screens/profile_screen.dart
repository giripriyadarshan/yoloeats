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
  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;

  RiskLevel? _selectedRiskLevel;
  List<String> _selectedAllergens = [];
  List<String> _selectedDietaryPrefs = [];

  bool _isInitialized = false;
  UserProfile? _loadedProfile;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _emailController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _updateFormState(UserProfile? profile) {
    if (!_isInitialized || _loadedProfile?.userId != profile?.userId) {
      _loadedProfile = profile;
      _usernameController.text = profile?.username ?? '';
      _emailController.text = profile?.email ?? '';
      _selectedRiskLevel = profile?.riskTolerance ?? RiskLevel.medium;
      _selectedAllergens = List<String>.from(profile?.allergens ?? []);
      _selectedDietaryPrefs = List<String>.from(profile?.dietaryPrefs ?? []);
      if (profile != null) {
        _isInitialized = true;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _saveProfile() {
    if (_loadedProfile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No profile loaded to update.')),
      );
      return;
    }

    final updatedProfile = _loadedProfile!.copyWith(
      username: _usernameController.text,
      email: _emailController.text,
      riskTolerance: _selectedRiskLevel,
      allergens: _selectedAllergens,
      dietaryPrefs: _selectedDietaryPrefs,
    );

    ref.read(userProfileProvider.notifier).saveProfile(updatedProfile).then((_) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save profile: $e')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final userProfileAsync = ref.watch(userProfileProvider);
    final allergensAsync = ref.watch(allergensProvider);

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
        loading: () => const Center(child: CircularProgressIndicator()),
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
        data: (profile) {
          return allergensAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error loading allergens: $err')),
            data: (availableAllergens) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('User ID: ${profile?.userId ?? "Not set"}'),
                    const SizedBox(height: 16),
                    TextFormField(controller: _usernameController, ),
                    const SizedBox(height: 16),
                    TextFormField(controller: _emailController, ),
                    const SizedBox(height: 24),
                    const Text('Allergy Risk Tolerance:', style: TextStyle(fontWeight: FontWeight.bold)),
                    DropdownButtonFormField<RiskLevel>(value: _selectedRiskLevel, items: RiskLevel.values.map((level) => DropdownMenuItem(value: level, child: Text(level.toString().split('.').last))).toList(), onChanged:(v) => setState(()=>_selectedRiskLevel=v) ),
                    const SizedBox(height: 24),

                    const Text('Allergens:', style: TextStyle(fontWeight: FontWeight.bold)),
                    if (availableAllergens.isEmpty)
                      const Text('No allergens available.')
                    else
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 4.0,
                        children: availableAllergens.map((allergen) {
                          final isSelected = _selectedAllergens.contains(allergen.id);
                          return ChoiceChip(
                            label: Text(allergen.name),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedAllergens.add(allergen.id);
                                } else {
                                  _selectedAllergens.remove(allergen.id);
                                }
                              });
                            },
                            tooltip: allergen.description,
                            selectedColor: Theme.of(context).colorScheme.primaryContainer,
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 24),

                    // --- Dietary Preferences (TODO - Similar structure as allergens) ---
                    const Text('Dietary Preferences:', style: TextStyle(fontWeight: FontWeight.bold)),
                    // TODO: Implement similar logic using a separate provider/list
                    Text('Selected: ${_selectedDietaryPrefs.join(", ")} (Widget TODO)'),
                    const SizedBox(height: 32),

                    ElevatedButton(
                      onPressed: _isInitialized ? _saveProfile : null,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: const Text('Save Profile'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}