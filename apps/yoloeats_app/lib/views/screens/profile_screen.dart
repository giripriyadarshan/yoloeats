import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yoloeats_app/models/user_profile.dart';
import 'package:yoloeats_app/providers/user_profile_providers.dart';
import 'package:yoloeats_app/providers/auth_providers.dart';
import '../../models/allergen_info.dart';

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

  bool _formInitializedFromData = false;

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

    if (!_formInitializedFromData && profile != null) {
      print("ProfileScreen: Initializing form fields from loaded profile data.");
      _usernameController.text = profile.username ?? '';
      _emailController.text = profile.email ?? '';
      setState(() {
        _selectedRiskLevel = profile.riskTolerance;
        _selectedAllergens = List<String>.from(profile.allergens);
        _selectedDietaryPrefs = List<String>.from(profile.dietaryPrefs);
      });
      _formInitializedFromData = true;
    } else if (profile == null) {
      print("ProfileScreen: Profile data is null, form not initialized from data.");
    }
  }

  void _saveProfile() {
    final userId = ref.read(currentUserIdProvider);

    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Error: Cannot save profile. User not identified.'),
            backgroundColor: Colors.red),
      );
      return;
    }

    final profileToSave = UserProfile(
      userId: userId,
      username: _usernameController.text.trim().isEmpty
          ? null
          : _usernameController.text.trim(),
      email: _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim(),
      riskTolerance: _selectedRiskLevel ?? RiskLevel.medium,
      allergens: _selectedAllergens,
      dietaryPrefs: _selectedDietaryPrefs,
    );

    print("ProfileScreen: Attempting to save profile for userId: $userId");

    ref.read(userProfileProvider.notifier).saveProfile(profileToSave).then((_) {
      final currentState = ref.read(userProfileProvider);
      if (mounted) {
        if (currentState is AsyncError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error saving profile: ${currentState.error}'),
                backgroundColor: Colors.red),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile saved!')),
          );
        }
      }
    }).catchError((e, s) {
      print("ProfileScreen: Error during saveProfile future: $e\n$s");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save profile: $e'), backgroundColor: Colors.red),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final userProfileAsync = ref.watch(userProfileProvider);
    final currentUserId = ref.watch(currentUserIdProvider);
    final allergensAsync = ref.watch(allergensProvider);

    final bool hasUserId = currentUserId != null && currentUserId.isNotEmpty;
    final bool canEdit = hasUserId;

    ref.listen<AsyncValue<UserProfile?>>(userProfileProvider, (_, next) {
      if (next is AsyncData<UserProfile?>) {
        _updateFormState(next.value);
      }
      if (next is AsyncLoading || next is AsyncError) {
        if (_formInitializedFromData) {
           _formInitializedFromData = false;
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: hasUserId && !userProfileAsync.isLoading
                ? () {
              _formInitializedFromData = false;
              ref.read(userProfileProvider.notifier).refreshProfile();
            }
                : null,
            tooltip: 'Refresh Profile',
          ),
        ],
      ),
      body: buildBody(context, userProfileAsync, allergensAsync, canEdit, currentUserId),
    );
  }

  Widget buildBody(
      BuildContext context,
      AsyncValue<UserProfile?> userProfileAsync,
      AsyncValue<List<AllergenInfo>> allergensAsync,
      bool canEdit,
      String? currentUserId) {

    if (!canEdit && currentUserId == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Identifying user..."),
          ],
        ),
      );
    }

    if (userProfileAsync is AsyncLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (userProfileAsync is AsyncError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error loading profile: ${userProfileAsync.error}', style: TextStyle(color: Colors.red)),
              const SizedBox(height: 10),
              if (canEdit)
                ElevatedButton(
                  onPressed: () {
                    _formInitializedFromData = false;
                    ref.read(userProfileProvider.notifier).refreshProfile();
                  },
                  child: const Text('Retry Load'),
                )
              else
                const Text("Cannot load profile: User not identified.", style: TextStyle(color: Colors.orange)),

              const SizedBox(height: 20),
              if(canEdit)
                const Text("You can still try to fill and save the form."),
            ],
          ),
        ),
      );
    }

    return allergensAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error loading allergens: $err', style: TextStyle(color: Colors.red))),
      data: (availableAllergens) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Opacity(
            opacity: canEdit ? 1.0 : 0.5,
            child: AbsorbPointer(
              absorbing: !canEdit,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (currentUserId != null)
                    Text('User ID: $currentUserId', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(labelText: 'Username (Optional)', border: OutlineInputBorder()),
                    enabled: canEdit,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email (Optional)', border: OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                    enabled: canEdit,
                  ),
                  const SizedBox(height: 24),

                  const Text('Allergy Risk Tolerance:', style: TextStyle(fontWeight: FontWeight.bold)),
                  DropdownButtonFormField<RiskLevel>(
                    value: _selectedRiskLevel,
                    items: RiskLevel.values
                        .map((level) => DropdownMenuItem(
                        value: level,
                        child: Text(level.name)))
                        .toList(),
                    onChanged: canEdit ? (v) => setState(() => _selectedRiskLevel = v) : null,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    disabledHint: Text(_selectedRiskLevel?.name ?? "Select Level"),
                  ),
                  const SizedBox(height: 24),

                  const Text('Known Allergens:', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (availableAllergens.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text('Allergen list loading or empty.'),
                    )
                  else
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children: availableAllergens.map((allergen) {
                        final isSelected = _selectedAllergens.contains(allergen.id);
                        return ChoiceChip(
                          label: Text(allergen.name),
                          selected: isSelected,
                          onSelected: canEdit ? (selected) {
                            setState(() {
                              if (selected) {
                                _selectedAllergens.add(allergen.id);
                              } else {
                                _selectedAllergens.remove(allergen.id);
                              }
                            });
                          } : null,
                          tooltip: allergen.description,
                          selectedColor: canEdit ? Theme.of(context).colorScheme.primaryContainer : Colors.grey[300],
                          labelStyle: TextStyle(color: (!canEdit && !isSelected) ? Colors.grey[500] : null),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 24),

                  // --- Dietary Preferences (Widget TODO) ---
                  const Text('Dietary Preferences:', style: TextStyle(fontWeight: FontWeight.bold)),
                  // TODO: Implement similar chip selection logic using a separate provider/list for available diets
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('Selected: ${_selectedDietaryPrefs.isNotEmpty ? _selectedDietaryPrefs.join(", ") : "None"} (Widget TODO)'),
                  ),
                  const SizedBox(height: 32),

                  ElevatedButton(
                    onPressed: canEdit ? _saveProfile : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                    child: userProfileAsync is AsyncLoading
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Profile'),
                  ),
                  if (!canEdit && currentUserId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text("Cannot edit profile at the moment.", style: TextStyle(color: Colors.grey)),
                    )
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}