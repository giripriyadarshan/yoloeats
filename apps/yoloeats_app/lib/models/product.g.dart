// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProductAdapter extends TypeAdapter<Product> {
  @override
  final int typeId = 4;

  @override
  Product read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Product(
      id: fields[0] as String,
      code: fields[1] as String,
      productName: fields[2] as String?,
      brandsTags: (fields[3] as List?)?.cast<String>(),
      quantity: fields[4] as String?,
      imageUrl: fields[5] as String?,
      ingredientsText: fields[6] as String?,
      categoriesTags: (fields[7] as List?)?.cast<String>(),
      labelsTags: (fields[8] as List?)?.cast<String>(),
      nutritionGradeFr: fields[9] as String?,
      tracesTags: (fields[10] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, Product obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.code)
      ..writeByte(2)
      ..write(obj.productName)
      ..writeByte(3)
      ..write(obj.brandsTags)
      ..writeByte(4)
      ..write(obj.quantity)
      ..writeByte(5)
      ..write(obj.imageUrl)
      ..writeByte(6)
      ..write(obj.ingredientsText)
      ..writeByte(7)
      ..write(obj.categoriesTags)
      ..writeByte(8)
      ..write(obj.labelsTags)
      ..writeByte(9)
      ..write(obj.nutritionGradeFr)
      ..writeByte(10)
      ..write(obj.tracesTags);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
