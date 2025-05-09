// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_profile.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserProfileAdapter extends TypeAdapter<UserProfile> {
  @override
  final int typeId = 0;

  @override
  UserProfile read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserProfile(
      userId: fields[0] as String,
      username: fields[1] as String?,
      email: fields[2] as String?,
      allergens: (fields[3] as List?)?.cast<String>(),
      dietaryPrefs: (fields[4] as List?)?.cast<String>(),
      riskTolerance: fields[5] as RiskLevel,
    );
  }

  @override
  void write(BinaryWriter writer, UserProfile obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.userId)
      ..writeByte(1)
      ..write(obj.username)
      ..writeByte(2)
      ..write(obj.email)
      ..writeByte(3)
      ..write(obj.allergens)
      ..writeByte(4)
      ..write(obj.dietaryPrefs)
      ..writeByte(5)
      ..write(obj.riskTolerance);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfileAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RiskLevelAdapter extends TypeAdapter<RiskLevel> {
  @override
  final int typeId = 1;

  @override
  RiskLevel read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return RiskLevel.low;
      case 1:
        return RiskLevel.medium;
      case 2:
        return RiskLevel.high;
      default:
        return RiskLevel.low;
    }
  }

  @override
  void write(BinaryWriter writer, RiskLevel obj) {
    switch (obj) {
      case RiskLevel.low:
        writer.writeByte(0);
        break;
      case RiskLevel.medium:
        writer.writeByte(1);
        break;
      case RiskLevel.high:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiskLevelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
