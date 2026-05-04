class AssetTypeOption {
  final String id;
  final String name;

  const AssetTypeOption({
    required this.id,
    required this.name,
  });

  factory AssetTypeOption.fromMap(Map<String, dynamic> map) {
    return AssetTypeOption(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Sin nombre',
    );
  }
}

class AssetItem {
  final String id;
  final String assetTag;
  final String? serialNumber;
  final String? brand;
  final String? model;
  final String status;
  final String? assetTypeId;
  final String? notes;

  const AssetItem({
    required this.id,
    required this.assetTag,
    required this.serialNumber,
    required this.brand,
    required this.model,
    required this.status,
    required this.assetTypeId,
    required this.notes,
  });

  factory AssetItem.fromMap(Map<String, dynamic> map) {
    return AssetItem(
      id: map['id']?.toString() ?? '',
      assetTag: map['asset_tag']?.toString() ?? 'Sin tag',
      serialNumber: map['serial_number']?.toString(),
      brand: map['brand']?.toString(),
      model: map['model']?.toString(),
      status: map['status']?.toString() ?? 'libre',
      assetTypeId: map['asset_type_id']?.toString(),
      notes: map['notes']?.toString(),
    );
  }
}
