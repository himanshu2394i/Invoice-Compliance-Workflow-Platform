// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bundle.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class QueuedPhotoAdapter extends TypeAdapter<QueuedPhoto> {
  @override
  final int typeId = 0;

  @override
  QueuedPhoto read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return QueuedPhoto(
      localId: fields[0] as String,
      localPath: fields[1] as String,
      documentType: fields[2] as String,
      label: fields[3] as String,
      isPrimary: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, QueuedPhoto obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.localId)
      ..writeByte(1)
      ..write(obj.localPath)
      ..writeByte(2)
      ..write(obj.documentType)
      ..writeByte(3)
      ..write(obj.label)
      ..writeByte(4)
      ..write(obj.isPrimary);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueuedPhotoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class QueuedBundleAdapter extends TypeAdapter<QueuedBundle> {
  @override
  final int typeId = 1;

  @override
  QueuedBundle read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return QueuedBundle(
      localId: fields[0] as String,
      invoiceNumber: fields[1] as String,
      entityGstin: fields[2] as String,
      buyerGstin: fields[3] as String,
      buyerName: fields[4] as String,
      invoiceDate: fields[5] as String,
      taxableAmount: fields[6] as double,
      totalAmount: fields[7] as double,
      photos: (fields[8] as List).cast<QueuedPhoto>(),
      status: fields[9] as String,
      syncError: fields[10] as String?,
      createdAtMs: fields[11] as int,
    );
  }

  @override
  void write(BinaryWriter writer, QueuedBundle obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.localId)
      ..writeByte(1)
      ..write(obj.invoiceNumber)
      ..writeByte(2)
      ..write(obj.entityGstin)
      ..writeByte(3)
      ..write(obj.buyerGstin)
      ..writeByte(4)
      ..write(obj.buyerName)
      ..writeByte(5)
      ..write(obj.invoiceDate)
      ..writeByte(6)
      ..write(obj.taxableAmount)
      ..writeByte(7)
      ..write(obj.totalAmount)
      ..writeByte(8)
      ..write(obj.photos)
      ..writeByte(9)
      ..write(obj.status)
      ..writeByte(10)
      ..write(obj.syncError)
      ..writeByte(11)
      ..write(obj.createdAtMs);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueuedBundleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
