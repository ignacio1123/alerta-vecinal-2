class AlertModel {
  final String id;
  final String type;
  final String sender;
  final String notes;
  final String location;
  final double? latitude;
  final double? longitude;
  final DateTime timestamp;
  final bool active;
  final int photoCount;
  final String color;
  final String icon;
  final String customLocation;
  final String reportCode;

  const AlertModel({
    required this.id,
    this.type = 'EMERGENCIA',
    required this.sender,
    required this.notes,
    this.location = '',
    this.latitude,
    this.longitude,
    required this.timestamp,
    required this.active,
    this.photoCount = 0,
    this.color = '#DC2626',
    this.icon = '🚨',
    this.customLocation = '',
    this.reportCode = '',
  });

  String get description => notes;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'sender': sender,
    'notes': notes,
    'location': location,
    'latitude': latitude,
    'longitude': longitude,
    'timestamp': timestamp.toIso8601String(),
    'active': active,
    'photoCount': photoCount,
    'color': color,
    'icon': icon,
    'customLocation': customLocation,
    'codigoReporte': reportCode,
  };

  factory AlertModel.fromJson(Map<String, dynamic> json) =>
      AlertModel.fromMap('${json['id'] ?? 'alert'}', json);

  factory AlertModel.fromMap(String id, Map<dynamic, dynamic> value) {
    final rawTimestamp = value['timestamp'];
    final timestamp = rawTimestamp is num
        ? DateTime.fromMillisecondsSinceEpoch(rawTimestamp.toInt())
        : DateTime.tryParse('$rawTimestamp') ?? DateTime.now();

    double? lat = (value['latitude'] as num?)?.toDouble();
    double? lng = (value['longitude'] as num?)?.toDouble();

    final customLoc = '${value['ubicacionIncidente'] ?? value['customLocation'] ?? ''}'.trim();
    if ((lat == null || lng == null) && customLoc.isNotEmpty) {
      final parsed = extractCoordinates(customLoc);
      if (parsed.$1 != null && parsed.$2 != null) {
        lat = parsed.$1;
        lng = parsed.$2;
      }
    }

    final rawPhotos = value['fotosTomadas'] ?? value['photoCount'] ?? 0;
    final photoCount = rawPhotos is num ? rawPhotos.toInt() : (int.tryParse('$rawPhotos') ?? 0);

    String code = '${value['codigoReporte'] ?? value['reportCode'] ?? ''}'.trim();
    if (code.isEmpty) {
      final ymd = '${timestamp.year}${timestamp.month.toString().padLeft(2, '0')}${timestamp.day.toString().padLeft(2, '0')}';
      final cleanId = id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      final suffix = cleanId.length >= 4 ? cleanId.substring(cleanId.length - 4).toUpperCase() : cleanId.padLeft(4, '0').toUpperCase();
      code = '#REP-$ymd-$suffix';
    }

    return AlertModel(
      id: id,
      type: '${value['tipo'] ?? value['type'] ?? 'EMERGENCIA'}',
      sender: '${value['emisor'] ?? value['sender'] ?? 'Vecino'}',
      notes: '${value['descripcion'] ?? value['notes'] ?? ''}',
      location: '${value['ubicacion'] ?? ''}',
      latitude: lat,
      longitude: lng,
      timestamp: timestamp,
      active: value['active'] != false,
      photoCount: photoCount,
      color: '${value['color'] ?? '#DC2626'}',
      icon: '${value['icon'] ?? value['icono'] ?? '🚨'}',
      customLocation: customLoc,
      reportCode: code,
    );
  }

  AlertModel copyWith({
    String? id,
    String? type,
    String? sender,
    String? notes,
    String? location,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    bool? active,
    int? photoCount,
    String? color,
    String? icon,
    String? customLocation,
    String? reportCode,
  }) {
    return AlertModel(
      id: id ?? this.id,
      type: type ?? this.type,
      sender: sender ?? this.sender,
      notes: notes ?? this.notes,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      active: active ?? this.active,
      photoCount: photoCount ?? this.photoCount,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      customLocation: customLocation ?? this.customLocation,
      reportCode: reportCode ?? this.reportCode,
    );
  }

  static (double?, double?) extractCoordinates(String text) {
    try {
      final regex = RegExp(r'([-+]?\d{1,2}\.\d+)[,\s]+([-+]?\d{1,3}\.\d+)');
      final match = regex.firstMatch(text);
      if (match != null) {
        final lat = double.tryParse(match.group(1)!);
        final lng = double.tryParse(match.group(2)!);
        return (lat, lng);
      }
    } catch (_) {}
    return (null, null);
  }
}
