import 'package:equatable/equatable.dart';
import 'package:hive/hive.dart';

part 'allergen_info.g.dart';

@HiveType(typeId: 2) // Assign a unique typeId (use next available)
class AllergenInfo extends Equatable {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String? description;

  const AllergenInfo({
    required this.id,
    required this.name,
    this.description,
  }) : super();

  // Factory for JSON deserialization
  factory AllergenInfo.fromJson(Map<String, dynamic> json) {
    return AllergenInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
    );
  }

  // Note: toJson might not be needed if we only fetch, but good practice
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
    };
  }

  @override
  List<Object?> get props => [id, name, description];
  @override
  bool? get stringify => true;
}