import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/alert_model.dart';
import '../services/alarm_player_service.dart';
import '../services/alarm_sync_service.dart';
import '../services/biometric_service.dart';
import '../services/manual_pdf_service.dart';
import '../services/native_alert_service.dart';
import '../theme/app_theme.dart';
import 'active_alert_dialog.dart';
import 'admin_screen.dart';
import 'register_screen.dart';
import 'settings_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final service = AlarmSyncService();
  StreamSubscription<AlertModel?>? sub;
  AlertModel? alert;
  List<EmergencyButton> buttons = [];
  List<XFile> photos = [];
  bool _isIgnoringBattery = true;
  String _seguridadPhone = '1414';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Validar si la alerta inicial ya expiró (> 15 min) o fue descartada en este dispositivo
    final initialAlert = service.currentAlert;
    if (initialAlert != null) {
      final key = service.getAlertKey(initialAlert);
      final ageInMinutes = DateTime.now().difference(initialAlert.timestamp).inMinutes;
      if (ageInMinutes >= 15 || service.isAlertDismissed(key)) {
        alert = null;
        service.currentAlert = null;
      } else {
        alert = initialAlert;
      }
    } else {
      alert = null;
    }

    buttons = service.buttons;
    sub = service.alertStream.listen(
      (a) => mounted ? setState(() => alert = a) : null,
    );
    service.buttonsStream.listen(
      (b) => mounted ? setState(() => buttons = b) : null,
    );
    _checkBattery();
    _loadSeguridadPhone();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!service.isRegistered) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RegisterScreen()),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Al volver a la app tras estar en segundo plano o suspendida:
      // Reconectar de inmediato con Firebase Realtime Database
      service.reconnect();
      _checkBattery();
    }
  }

  Future<void> _loadSeguridadPhone() async {
    final phone = await service.getSeguridadCiudadanaPhone();
    if (mounted) setState(() => _seguridadPhone = phone);
  }

  Future<void> _checkBattery() async {
    final status = await NativeAlertService.isIgnoringBatteryOptimizations();
    if (mounted) setState(() => _isIgnoringBattery = status);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AlarmPlayerService().stopAlarm();
    sub?.cancel();
    super.dispose();
  }

  Future<Position?> _gps({
    LocationAccuracy desiredAccuracy = LocationAccuracy.best,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      // 1. Obtener la última posición conocida de inmediato (0 ms de espera)
      final lastKnown = await Geolocator.getLastKnownPosition();

      // 2. Intentar posición precisa actual con timeout optimizado para no demorar alarmas
      final LocationSettings settings = Platform.isAndroid
          ? AndroidSettings(
              accuracy: desiredAccuracy,
              distanceFilter: 0,
              forceLocationManager: false,
              intervalDuration: const Duration(milliseconds: 500),
              timeLimit: timeout,
            )
          : LocationSettings(
              accuracy: desiredAccuracy,
              timeLimit: timeout,
            );

      try {
        final pos = await Geolocator.getCurrentPosition(locationSettings: settings);
        return pos;
      } catch (_) {
        return lastKnown;
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final img = await picker.pickImage(source: source, imageQuality: 75);
      if (img != null) {
        setState(() => photos.add(img));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al capturar foto: $e')),
        );
      }
    }
  }

  void _previewPhoto(XFile file, int index) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Image.file(
                File(file.path),
                fit: BoxFit.contain,
                height: 350,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () {
                      setState(() => photos.removeAt(index));
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Eliminar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send(EmergencyButton button) async {
    // 1. Verificar si el vecino está activo en la villa
    final isActive = await service.isNeighborActive();
    if (!isActive) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.block, color: Colors.red),
              SizedBox(width: 8),
              Text('Cuenta Desactivada'),
            ],
          ),
          content: const Text(
            'Tu dispositivo ha sido desactivado en el sistema por la administración comunitaria.\n\nNo puedes emitir alertas hasta que un Administrador reactive tu cuenta.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;

    // Iniciar obtención de GPS de inmediato en segundo plano para rapidez
    Position? prePosition;
    _gps().then((p) {
      prePosition = p;
    }).catchError((_) {});

    final descCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    int locationOption = 0;
    bool isAwayFromHome = false;
    bool isLocatingGps = false;
    double? detectedLat;
    double? detectedLng;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final bool isDescRequired = button.requiresDescription &&
              button.id != '1' &&
              button.id != '2' &&
              button.id != '3';

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            title: Row(
              children: [
                Text(button.icon, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        button.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Confirmación de Alerta de Emergencia',
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Ubicación del incidente (3 Opciones: Casa, Vía Pública, Mapa Interactivo)
                  const Text('📍 Ubicación del Incidente:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                    ),
                    child: Column(
                      children: [
                        // Opción 1: En mi domicilio registrado
                        RadioListTile<int>(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                          title: const Text('En mi domicilio registrado', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          subtitle: Text(service.fullAddress.isNotEmpty ? service.fullAddress : 'Mi casa', style: const TextStyle(fontSize: 11)),
                          value: 0,
                          groupValue: locationOption,
                          onChanged: (val) {
                            setDialogState(() {
                              locationOption = 0;
                              isAwayFromHome = false;
                              locCtrl.clear();
                            });
                          },
                        ),
                        const Divider(height: 1),
                        // Opción 2: Fuera de casa / En la vía pública (GPS o texto)
                        RadioListTile<int>(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                          title: const Text('Fuera de casa / En la vía pública', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          subtitle: const Text('Detectar GPS rápido o escribir pasaje/calle', style: TextStyle(fontSize: 11)),
                          value: 1,
                          groupValue: locationOption,
                          onChanged: (val) async {
                            setDialogState(() {
                              locationOption = 1;
                              isAwayFromHome = true;
                              isLocatingGps = true;
                            });
                            final p = prePosition ?? await _gps();
                            if (p != null) {
                              detectedLat = p.latitude;
                              detectedLng = p.longitude;
                              locCtrl.text = '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
                            }
                            setDialogState(() {
                              isLocatingGps = false;
                            });
                          },
                        ),
                        const Divider(height: 1),
                        // Opción 3: Marcar en Mapa Interactivo (Sin salir de la app)
                        RadioListTile<int>(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                          title: const Text('🗺️ Marcar en Mapa Interactivo', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          subtitle: const Text('Abre el mapa de la villa sin salir de la app para marcar el punto', style: TextStyle(fontSize: 11)),
                          value: 2,
                          groupValue: locationOption,
                          onChanged: (val) async {
                            final p = prePosition ?? await _gps();
                            if (!dialogCtx.mounted) return;
                            final useLat = detectedLat ?? p?.latitude ?? -36.9568766;
                            final useLng = detectedLng ?? p?.longitude ?? -73.1517670;
                            final picked = await _openMapLocationPicker(
                              dialogCtx,
                              initialLat: useLat,
                              initialLng: useLng,
                            );
                            if (picked != null) {
                              setDialogState(() {
                                detectedLat = picked.$1;
                                detectedLng = picked.$2;
                                locCtrl.text = '${picked.$1.toStringAsFixed(5)}, ${picked.$2.toStringAsFixed(5)} (${picked.$3})';
                                locationOption = 1; // Se guarda directamente en fuera de casa / vía pública
                                isAwayFromHome = true;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  if (isAwayFromHome) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: locCtrl,
                            decoration: InputDecoration(
                              hintText: 'Ej. Pasaje 3 esquina Catrileo o link',
                              prefixIcon: isLocatingGps
                                  ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
                                  : const Icon(Icons.my_location, size: 18),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Detectar mi GPS ahora',
                          icon: const Icon(Icons.gps_fixed, color: AppColors.steelBlue),
                          onPressed: () async {
                            setDialogState(() => isLocatingGps = true);
                            final p = await _gps();
                            if (p != null) {
                              detectedLat = p.latitude;
                              detectedLng = p.longitude;
                              locCtrl.text = '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
                            }
                            setDialogState(() => isLocatingGps = false);
                          },
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 12),

                  // 2. Descripción (Opcional en los 3 botones principales de pánico)
                  Row(
                    children: [
                      Text(
                        isDescRequired ? '📝 ¿Qué está sucediendo? *' : '📝 ¿Qué está sucediendo? (Opcional)',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Text(
                        isDescRequired ? '(Obligatorio)' : '(Opcional)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDescRequired ? Colors.red.shade700 : (isDark ? Colors.white60 : Colors.black54),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    autofocus: isDescRequired,
                    decoration: InputDecoration(
                      hintText: isDescRequired
                          ? 'Describe lo que viste para emitir este reporte especial...'
                          : 'Opcional: Describe brevemente lo que viste o déjalo vacío para sonar de inmediato',
                    ),
                  ),

                  // 3. Fotos si las hay
                  if (photos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('📷 ${photos.length} foto(s) de evidencia lista(s) para enviar',
                          style: TextStyle(fontSize: 11, color: Colors.blue.shade900, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _parseColor(button.color),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onPressed: () {
                  final text = descCtrl.text.trim();
                  if (isDescRequired && text.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        backgroundColor: Colors.red,
                        content: Text('⚠️ Debes ingresar una descripción de lo sucedido para este botón personalizado.'),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(dialogCtx, true);
                },
                icon: const Icon(Icons.warning, size: 16),
                label: const Text('HACER SONAR ALARMA', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    String description = descCtrl.text.trim();
    if (description.isEmpty) {
      description = 'Alerta de ${button.title} activada de inmediato por vecino.';
    }
    String customLoc = locCtrl.text.trim();
    final int photoCount = button.allowsPhotos ? photos.length : 0;
    if (photoCount > 0) {
      final photoNotice = '[$photoCount fotos registradas]';
      description = '$description $photoNotice';
    }

    Position? pos;
    double? alertLat = detectedLat;
    double? alertLng = detectedLng;

    if (customLoc.isNotEmpty) {
      final parsed = AlertModel.extractCoordinates(customLoc);
      if (parsed.$1 != null && parsed.$2 != null) {
        alertLat = parsed.$1;
        alertLng = parsed.$2;
      }
    }

    if (alertLat == null || alertLng == null) {
      try {
        pos = prePosition ?? await _gps();
        alertLat = pos?.latitude;
        alertLng = pos?.longitude;
      } catch (_) {}
    }

    final String finalLocation = customLoc.isNotEmpty
        ? customLoc
        : (alertLat != null ? '$alertLat, $alertLng' : service.fullAddress);

    try {
      await service.sendEmergencyAlert(
        type: button.title,
        description: description,
        location: finalLocation,
        latitude: alertLat,
        longitude: alertLng,
        photoCount: photoCount,
        color: button.color,
        icon: button.icon,
        customLocation: customLoc,
      );

      if (photoCount > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 6),
            content: Text('Alerta emitida con $photoCount foto(s) de evidencia.'),
            action: SnackBarAction(
              label: 'ENVIAR A WSP',
              textColor: Colors.white,
              onPressed: _sharePhotosViaWhatsApp,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 5),
            content: Text(
              '⚠️ Alerta iniciada en tu teléfono, pero falló el envío a Firebase: $e',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    }
  }

  Future<(double, double, String)?> _openMapLocationPicker(
    BuildContext context, {
    double? initialLat,
    double? initialLng,
  }) async {
    final allKnownStreets = [
      ('Calle Catrileo (Eje Principal)', -36.9568766, -73.1517670, 'Las Galileas'),
      ('Catrileo con Av. Las Torres', -36.9568361, -73.1505658, 'Las Galileas'),
      ('Catrileo con Pasaje Paillao', -36.9567873, -73.1491216, 'Las Galileas'),
      ('Catrileo con Pasaje Regumilla', -36.9567489, -73.1479850, 'Las Galileas'),
      ('Catrileo con Av. Galvarino', -36.9567251, -73.1472784, 'Las Galileas'),
      ('Pasaje Llinko', -36.9569098, -73.1527504, 'Las Galileas'),
      ('Calle Wennmapu', -36.9569172, -73.1529682, 'Las Galileas'),
      ('Pasaje Curamil', -36.9580744, -73.1498388, 'Las Galileas'),
      ('Pasaje Chiguay', -36.9598132, -73.1483995, 'Las Galileas'),
      ('Pasaje Paillao', -36.9607119, -73.1477798, 'Las Galileas'),
      ('Pasaje Regumilla', -36.9584076, -73.1490288, 'Las Galileas'),
      ('Avenida Las Torres', -36.9568361, -73.1505658, 'Las Galileas'),
      ('Avenida Galvarino', -36.9586943, -73.1433339, 'Las Galileas'),
      ('Avenida Villa Verde (Entrada Las Galileas)', -36.9555000, -73.1530000, 'Villa Verde / Escuadrón'),
      ('Calle Michimalonco', -36.9584995, -73.1516936, 'Las Galileas'),
      ('Calle Guacolda', -36.9580000, -73.1510000, 'Las Galileas'),
      ('Plaza / Multicancha Las Galileas', -36.9572000, -73.1505000, 'Área Verde Las Galileas'),
      ('Calle Caupolicán', -36.9473333, -73.1537947, 'Sector Escuadrón'),
      ('Calle Fresia', -36.9510831, -73.1528205, 'Parque La Posada'),
      ('Cruce Escuadrón / Ruta 160', -36.9540000, -73.1550000, 'Acceso Principal'),
      ('Calle Lautaro', -37.0280075, -73.1371634, 'Coronel'),
      ('Calle Colo Colo', -37.0300000, -73.1380000, 'Coronel'),
    ];

    // Domicilio dinámico del vecino registrado en este dispositivo
    double myHomeLat = -36.9568766;
    double myHomeLng = -73.1517670;
    String myHomeTitle = 'Mi Casa';

    if (service.fullAddress.isNotEmpty) {
      myHomeTitle = 'Mi Casa (${service.fullAddress})';
      final cleanAddr = service.fullAddress.toLowerCase();
      if (cleanAddr.contains('curamil')) {
        myHomeLat = -36.9580744; myHomeLng = -73.1498388;
      } else if (cleanAddr.contains('llinko')) {
        myHomeLat = -36.9569098; myHomeLng = -73.1527504;
      } else if (cleanAddr.contains('wennmapu')) {
        myHomeLat = -36.9569172; myHomeLng = -73.1529682;
      } else if (cleanAddr.contains('paillao')) {
        myHomeLat = -36.9607119; myHomeLng = -73.1477798;
      } else if (cleanAddr.contains('regumilla')) {
        myHomeLat = -36.9584076; myHomeLng = -73.1490288;
      } else if (cleanAddr.contains('torres')) {
        myHomeLat = -36.9568361; myHomeLng = -73.1505658;
      } else if (cleanAddr.contains('galvarino')) {
        myHomeLat = -36.9586943; myHomeLng = -73.1433339;
      } else if (cleanAddr.contains('michimalonco')) {
        myHomeLat = -36.9584995; myHomeLng = -73.1516936;
      } else if (cleanAddr.contains('guacolda')) {
        myHomeLat = -36.9580000; myHomeLng = -73.1510000;
      } else if (cleanAddr.contains('catrileo')) {
        myHomeLat = -36.9568766; myHomeLng = -73.1517670;
      }
    } else {
      myHomeTitle = 'Catrileo 2430 (Mi Casa)';
    }

    double currentLat = initialLat ?? myHomeLat;
    double currentLng = initialLng ?? myHomeLng;
    double? phoneLat;
    double? phoneLng;
    double? phoneAccuracy;
    bool hasRequestedPhoneGps = false;
    bool isSatellite = false;
    bool isFetchingGps = false;
    bool isSearchingOnline = false;
    final MapController mapController = MapController();
    final TextEditingController searchCtrl = TextEditingController();
    final FocusNode searchFocus = FocusNode();
    List<(String, double, double, String)> searchResults = [];

    final landmarks = [
      (myHomeTitle, myHomeLat, myHomeLng, 25.0),
      ('Catrileo 2430 (Base Las Galileas)', -36.9568766, -73.1517670, 25.0),
      ('Catrileo con Av. Las Torres', -36.9568361, -73.1505658, 30.0),
      ('Catrileo con Paillao', -36.9567873, -73.1491216, 30.0),
      ('Catrileo con Regumilla', -36.9567489, -73.1479850, 30.0),
      ('Catrileo con Av. Galvarino', -36.9567251, -73.1472784, 30.0),
      ('Pasaje Llinko (Las Galileas)', -36.9569098, -73.1527504, 25.0),
      ('Calle Wennmapu (Las Galileas)', -36.9569172, -73.1529682, 25.0),
      ('Av. Villa Verde (Acceso Las Galileas)', -36.9555000, -73.1530000, 40.0),
      ('Calle Guacolda (Las Galileas)', -36.9580000, -73.1510000, 30.0),
      ('Calle Michimalonco', -36.9585000, -73.1500000, 30.0),
      ('Plaza / Multicancha Las Galileas', -36.9572000, -73.1505000, 35.0),
      ('Pasaje Curamil (Las Galileas)', -36.9580744, -73.1498388, 30.0),
      ('Pasaje Chiguay (Las Galileas)', -36.9598132, -73.1483995, 30.0),
      ('Calle Caupolicán (Escuadrón)', -36.9473333, -73.1537947, 40.0),
      ('Calle Fresia (Parque La Posada)', -36.9510831, -73.1528205, 40.0),
    ];

    double distMeters(double lat1, double lng1, double lat2, double lng2) {
      final dy = (lat1 - lat2) * 111000.0;
      final dx = (lng1 - lng2) * 88000.0;
      return math.sqrt(dx * dx + dy * dy);
    }

    String resolveLocationInfo(double lat, double lng) {
      for (final lm in landmarks) {
        final d = distMeters(lat, lng, lm.$2, lm.$3);
        if (d <= lm.$4) {
          return lm.$1;
        }
      }
      if (lat >= -36.9573 && lat <= -36.9564 && lng >= -73.1535 && lng <= -73.1470) {
        return 'Calle Catrileo, Las Galileas (${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)})';
      }
      return 'Las Galileas, Coronel (${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)})';
    }

    String selectedLabel = resolveLocationInfo(currentLat, currentLng);

    final quickLandmarks = [
      {'name': myHomeTitle, 'icon': '🏠', 'lat': myHomeLat, 'lng': myHomeLng},
      {'name': 'Catrileo / Las Torres', 'icon': '🛣️', 'lat': -36.9568361, 'lng': -73.1505658},
      {'name': 'Catrileo / Paillao', 'icon': '🛣️', 'lat': -36.9567873, 'lng': -73.1491216},
      {'name': 'Catrileo / Regumilla', 'icon': '🛣️', 'lat': -36.9567489, 'lng': -73.1479850},
      {'name': 'Pje. Curamil', 'icon': '🛣️', 'lat': -36.9580744, 'lng': -73.1498388},
      {'name': 'Pje. Llinko', 'icon': '🛣️', 'lat': -36.9569098, 'lng': -73.1527504},
      {'name': 'Wennmapu', 'icon': '🛣️', 'lat': -36.9569172, 'lng': -73.1529682},
      {'name': 'Av. Villa Verde', 'icon': '🚪', 'lat': -36.9555000, 'lng': -73.1530000},
      {'name': 'Cancha / Plaza', 'icon': '⚽', 'lat': -36.9572000, 'lng': -73.1505000},
    ];

    return showDialog<(double, double, String)?>(
      context: context,
      barrierDismissible: false,
      builder: (pickerCtx) => StatefulBuilder(
        builder: (ctx, setPickerState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final screenH = MediaQuery.of(ctx).size.height;

          // Obtener GPS del teléfono automáticamente como referencia si aún no se tiene
          if (!hasRequestedPhoneGps) {
            hasRequestedPhoneGps = true;
            Geolocator.getLastKnownPosition().then((pos) {
              if (pos != null && phoneLat == null) {
                setPickerState(() {
                  phoneLat = pos.latitude;
                  phoneLng = pos.longitude;
                  phoneAccuracy = pos.accuracy;
                });
              }
            });
            _gps(desiredAccuracy: LocationAccuracy.best, timeout: const Duration(seconds: 12)).then((pos) {
              if (pos != null) {
                setPickerState(() {
                  phoneLat = pos.latitude;
                  phoneLng = pos.longitude;
                  phoneAccuracy = pos.accuracy;
                });
              }
            });
          }

          Future<void> openExternalGoogleMaps() async {
            final uri = Uri.parse(
              'https://www.google.com/maps/search/?api=1&query=$currentLat,$currentLng',
            );
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }

          void performStreetSearch(String query) async {
            final cleanQuery = query.trim().toLowerCase();
            if (cleanQuery.isEmpty) {
              setPickerState(() {
                searchResults = [];
                isSearchingOnline = false;
              });
              return;
            }

            final localMatches = allKnownStreets.where((item) {
              final sName = item.$1.toLowerCase();
              final sector = item.$4.toLowerCase();
              return sName.contains(cleanQuery) || sector.contains(cleanQuery);
            }).toList();

            setPickerState(() {
              searchResults = localMatches;
            });

            if (cleanQuery.length >= 3) {
              setPickerState(() => isSearchingOnline = true);
              try {
                final uri = Uri.parse(
                  'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent('$cleanQuery, Coronel, Biobio, Chile')}&format=json&limit=5&viewbox=-73.18,-36.93,-73.12,-36.99',
                );
                final res = await http.get(
                  uri,
                  headers: {'User-Agent': 'AlertaVecinal-App/1.0'},
                ).timeout(const Duration(seconds: 4));

                if (res.statusCode == 200) {
                  final List<dynamic> data = jsonDecode(res.body);
                  final onlineMatches = <(String, double, double, String)>[];
                  for (final item in data) {
                    final dName = item['display_name'] as String? ?? cleanQuery;
                    final lat = double.tryParse(item['lat']?.toString() ?? '');
                    final lon = double.tryParse(item['lon']?.toString() ?? '');
                    if (lat != null && lon != null) {
                      final shortName = dName.split(',').take(2).join(',').trim();
                      onlineMatches.add((shortName, lat, lon, 'Mapa Coronel (OSM)'));
                    }
                  }
                  if (onlineMatches.isNotEmpty) {
                    setPickerState(() {
                      final existingNames = localMatches.map((m) => m.$1.toLowerCase()).toSet();
                      final filteredOnline = onlineMatches.where((om) => !existingNames.contains(om.$1.toLowerCase()));
                      searchResults = [...localMatches, ...filteredOnline];
                      isSearchingOnline = false;
                    });
                    return;
                  }
                }
              } catch (_) {}
              setPickerState(() => isSearchingOnline = false);
            }
          }

          void selectStreetResult((String, double, double, String) item) {
            setPickerState(() {
              currentLat = item.$2;
              currentLng = item.$3;
              selectedLabel = item.$1;
              searchResults = [];
              searchCtrl.text = item.$1;
            });
            searchFocus.unfocus();
            mapController.move(latlong.LatLng(item.$2, item.$3), 18.0);
          }

          // Distancia de referencia entre el teléfono y el pin del incidente
          int? distToPhoneMeters;
          if (phoneLat != null && phoneLng != null) {
            distToPhoneMeters = distMeters(phoneLat!, phoneLng!, currentLat, currentLng).round();
          }

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Container(
              height: screenH * 0.92,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                children: [
                  // 1. Cabecera accesible con botón de cerrar
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.steelBlue.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.map_rounded, color: AppColors.steelBlue, size: 24),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🗺️ Mapa Las Galileas (Coronel)',
                              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Busca tu calle o toca el mapa para marcar el incidente',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 22),
                        onPressed: () => Navigator.pop(pickerCtx, null),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // 2. Buscador de Calles y Pasajes con autocompletado
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFF3B82F6),
                        width: 1.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: searchCtrl,
                      focusNode: searchFocus,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '🔍 Escribe calle o pasaje (ej: Paillao, Catrileo)...',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.grey.shade600,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: InputBorder.none,
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSearchingOnline)
                              const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            else if (searchCtrl.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 17),
                                onPressed: () {
                                  searchCtrl.clear();
                                  performStreetSearch('');
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.search, color: Color(0xFF2563EB), size: 20),
                              tooltip: 'Buscar en mapa',
                              onPressed: () => performStreetSearch(searchCtrl.text),
                            ),
                          ],
                        ),
                      ),
                      onChanged: performStreetSearch,
                      onSubmitted: performStreetSearch,
                    ),
                  ),

                  // Sugerencias de búsqueda desplegables
                  if (searchResults.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 150),
                      margin: const EdgeInsets.only(top: 4, bottom: 4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF2563EB), width: 1.5),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: searchResults.length,
                        separatorBuilder: (context, index) => Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade300),
                        itemBuilder: (c, idx) {
                          final item = searchResults[idx];
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: const Icon(Icons.location_on, color: Color(0xFF2563EB), size: 18),
                            title: Text(
                              item.$1,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                            subtitle: Text(
                              item.$4,
                              style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white70 : Colors.black54),
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
                            onTap: () => selectStreetResult(item),
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 6),

                  // 3. Banner Destacado del Punto Seleccionado con Distancia de Referencia
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF2563EB),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.red, size: 26),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedLabel,
                                style: const TextStyle(
                                  fontSize: 13.0,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1D4ED8),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Row(
                                children: [
                                  Text(
                                    'Lat: ${currentLat.toStringAsFixed(5)}, Lng: ${currentLng.toStringAsFixed(5)}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: isDark ? Colors.white70 : Colors.black54,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (distToPhoneMeters != null) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1D4ED8).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '📱 A ${distToPhoneMeters}m de ti',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF1D4ED8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: openExternalGoogleMaps,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade300),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.open_in_new, size: 13, color: Color(0xFF1D4ED8)),
                                SizedBox(width: 3),
                                Text(
                                  'Google Maps',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1D4ED8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 6),

                  // 4. Mapa Real Interactivo con FlutterMap (Calles OSM / Satélite Esri)
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                          border: Border.all(
                            color: isDark ? const Color(0xFF333B48) : Colors.grey.shade400,
                            width: 1.5,
                          ),
                        ),
                        child: Stack(
                          children: [
                            FlutterMap(
                              mapController: mapController,
                              options: MapOptions(
                                initialCenter: latlong.LatLng(currentLat, currentLng),
                                initialZoom: 18.0,
                                minZoom: 13.0,
                                maxZoom: 19.0,
                                interactionOptions: const InteractionOptions(
                                  flags: InteractiveFlag.all,
                                ),
                                onTap: (tapPosition, point) {
                                  final newLabel = resolveLocationInfo(point.latitude, point.longitude);
                                  setPickerState(() {
                                    currentLat = point.latitude;
                                    currentLng = point.longitude;
                                    selectedLabel = newLabel;
                                  });
                                },
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: isSatellite
                                      ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.comunidad.alerta.alerta_vecinal_app',
                                  maxZoom: 19,
                                ),
                                if (phoneLat != null && phoneLng != null && phoneAccuracy != null && phoneAccuracy! < 150)
                                  CircleLayer(
                                    circles: [
                                      CircleMarker(
                                        point: latlong.LatLng(phoneLat!, phoneLng!),
                                        radius: phoneAccuracy!.clamp(4.0, 50.0),
                                        useRadiusInMeter: true,
                                        color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                                        borderColor: const Color(0xFF2563EB).withValues(alpha: 0.6),
                                        borderStrokeWidth: 1.5,
                                      ),
                                    ],
                                  ),
                                MarkerLayer(
                                  markers: [
                                    // A) Marcador de Referencia del Teléfono del Vecino (Azul)
                                    if (phoneLat != null && phoneLng != null)
                                      Marker(
                                        point: latlong.LatLng(phoneLat!, phoneLng!),
                                        width: 95,
                                        height: 60,
                                        alignment: Alignment.topCenter,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF1D4ED8),
                                                borderRadius: BorderRadius.circular(5),
                                                boxShadow: const [
                                                  BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                                                ],
                                              ),
                                              child: Text(
                                                phoneAccuracy != null && phoneAccuracy! > 0
                                                    ? '📱 Mi Teléfono (±${phoneAccuracy!.round()}m)'
                                                    : '📱 Mi Teléfono',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 1),
                                            Container(
                                              width: 26,
                                              height: 26,
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade600,
                                                shape: BoxShape.circle,
                                                border: Border.all(color: Colors.white, width: 2),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.blue.withValues(alpha: 0.5),
                                                    blurRadius: 6,
                                                    spreadRadius: 2,
                                                  ),
                                                ],
                                              ),
                                              child: const Icon(
                                                Icons.person_pin_circle,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                    // B) Marcador de la Emergencia / Incidente (Rojo)
                                    Marker(
                                      point: latlong.LatLng(currentLat, currentLng),
                                      width: 80,
                                      height: 65,
                                      alignment: Alignment.topCenter,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade700,
                                              borderRadius: BorderRadius.circular(6),
                                              boxShadow: const [
                                                BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
                                              ],
                                            ),
                                            child: const Text(
                                              '🚨 INCIDENTE',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const Icon(
                                            Icons.location_on,
                                            color: Colors.redAccent,
                                            size: 38,
                                            shadows: [
                                              Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            // Alternador de Capa: [🗺️ Calles] / [🛰️ Satélite]
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: const EdgeInsets.all(3),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    InkWell(
                                      onTap: () => setPickerState(() => isSatellite = false),
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: !isSatellite ? const Color(0xFF2563EB) : Colors.transparent,
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: const Text(
                                          '🗺️ Calles',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () => setPickerState(() => isSatellite = true),
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isSatellite ? const Color(0xFF2563EB) : Colors.transparent,
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: const Text(
                                          '🛰️ Satélite',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Botones Flotantes de Zoom, Re-centrar Pin y Re-centrar Teléfono
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Column(
                                children: [
                                  FloatingActionButton.small(
                                    heroTag: 'map_zoom_in',
                                    backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                    foregroundColor: AppColors.steelBlue,
                                    elevation: 4,
                                    tooltip: 'Acercar (+)',
                                    onPressed: () {
                                      final currentZoom = mapController.camera.zoom;
                                      mapController.move(mapController.camera.center, (currentZoom + 1.0).clamp(13.0, 19.0));
                                    },
                                    child: const Icon(Icons.add, size: 20),
                                  ),
                                  const SizedBox(height: 5),
                                  FloatingActionButton.small(
                                    heroTag: 'map_zoom_out',
                                    backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                    foregroundColor: AppColors.steelBlue,
                                    elevation: 4,
                                    tooltip: 'Alejar (-)',
                                    onPressed: () {
                                      final currentZoom = mapController.camera.zoom;
                                      mapController.move(mapController.camera.center, (currentZoom - 1.0).clamp(13.0, 19.0));
                                    },
                                    child: const Icon(Icons.remove, size: 20),
                                  ),
                                  const SizedBox(height: 5),
                                  FloatingActionButton.small(
                                    heroTag: 'map_center_pin',
                                    backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                    foregroundColor: Colors.red.shade700,
                                    elevation: 4,
                                    tooltip: 'Centrar en el Incidente',
                                    onPressed: () {
                                      mapController.move(latlong.LatLng(currentLat, currentLng), mapController.camera.zoom);
                                    },
                                    child: const Icon(Icons.my_location, size: 19),
                                  ),
                                  if (phoneLat != null && phoneLng != null) ...[
                                    const SizedBox(height: 5),
                                    FloatingActionButton.small(
                                      heroTag: 'map_center_phone',
                                      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                      foregroundColor: const Color(0xFF1D4ED8),
                                      elevation: 4,
                                      tooltip: 'Ver Dónde Está Mi Teléfono',
                                      onPressed: () {
                                        mapController.move(latlong.LatLng(phoneLat!, phoneLng!), 18.0);
                                      },
                                      child: const Icon(Icons.phone_android, size: 19),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // Botón GPS actual en la esquina inferior derecha
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                  foregroundColor: AppColors.steelBlue,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: isFetchingGps
                                    ? null
                                    : () async {
                                        setPickerState(() => isFetchingGps = true);
                                        final p = await _gps(
                                          desiredAccuracy: LocationAccuracy.best,
                                          timeout: const Duration(seconds: 15),
                                        );
                                        if (p != null) {
                                          String resolvedName = resolveLocationInfo(p.latitude, p.longitude);
                                          try {
                                            final uri = Uri.parse(
                                              'https://nominatim.openstreetmap.org/reverse?lat=${p.latitude}&lon=${p.longitude}&format=json&zoom=18&addressdetails=1',
                                            );
                                            final res = await http.get(
                                              uri,
                                              headers: {'User-Agent': 'AlertaVecinal-App/1.0'},
                                            ).timeout(const Duration(seconds: 4));
                                            if (res.statusCode == 200) {
                                              final data = jsonDecode(res.body);
                                              final addr = data['address'] as Map<String, dynamic>?;
                                              if (addr != null) {
                                                final road = addr['road'] ?? addr['pedestrian'] ?? addr['path'] ?? addr['suburb'];
                                                final houseNumber = addr['house_number'];
                                                if (road != null) {
                                                  resolvedName = houseNumber != null
                                                      ? '$road #$houseNumber, Galileas'
                                                      : '$road, Las Galileas';
                                                }
                                              }
                                            }
                                          } catch (_) {}

                                          final accStr = p.accuracy > 0 ? ' (±${p.accuracy.round()}m)' : '';
                                          setPickerState(() {
                                            currentLat = p.latitude;
                                            currentLng = p.longitude;
                                            phoneLat = p.latitude;
                                            phoneLng = p.longitude;
                                            phoneAccuracy = p.accuracy;
                                            selectedLabel = 'GPS: $resolvedName$accStr';
                                            isFetchingGps = false;
                                          });
                                          mapController.move(latlong.LatLng(p.latitude, p.longitude), 18.5);
                                        } else {
                                          setPickerState(() => isFetchingGps = false);
                                        }
                                      },
                                icon: isFetchingGps
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.gps_fixed, size: 16),
                                label: const Text('📍 Usar Mi GPS', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  // 5. Puntos Clave de 1-Toque (Villa Escuadrón Galilea)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: quickLandmarks.map((lm) {
                        final name = lm['name'] as String;
                        final icon = lm['icon'] as String;
                        final lmLat = lm['lat'] as double;
                        final lmLng = lm['lng'] as double;
                        final isSel = selectedLabel.startsWith(name);

                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              final newLabel = resolveLocationInfo(lmLat, lmLng);
                              setPickerState(() {
                                currentLat = lmLat;
                                currentLng = lmLng;
                                selectedLabel = newLabel;
                              });
                              mapController.move(latlong.LatLng(lmLat, lmLng), 18.0);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? const Color(0xFF1D4ED8)
                                    : (isDark ? const Color(0xFF1E293B) : Colors.grey.shade200),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSel ? Colors.blueAccent : Colors.transparent,
                                  width: 1.4,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(icon, style: const TextStyle(fontSize: 12)),
                                  const SizedBox(width: 4),
                                  Text(
                                    name,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                                      color: isSel ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 6. Botones de Acción Final
                  Row(
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        onPressed: () => Navigator.pop(pickerCtx, null),
                        child: const Text('Cancelar', style: TextStyle(fontSize: 13.5)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            elevation: 3,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            Navigator.pop(pickerCtx, (currentLat, currentLng, selectedLabel));
                          },
                          icon: const Icon(Icons.check_circle, size: 18),
                          label: const Text(
                            '✓ CONFIRMAR UBICACIÓN',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showEditProfileDialog() async {
    final attempts = await service.getEditProfileAttempts();
    final firstCtrl = TextEditingController(text: service.firstName);
    final l1Ctrl = TextEditingController(text: service.lastName1);
    final l2Ctrl = TextEditingController(text: service.lastName2);
    final addrCtrl = TextEditingController(text: service.address);
    final houseCtrl = TextEditingController(text: service.houseNumber);

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final isLocked = attempts >= 3;
          final remaining = 3 - attempts;
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  isLocked ? Icons.lock : Icons.manage_accounts,
                  color: isLocked ? Colors.red : AppColors.steelBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isLocked ? 'Datos Bloqueados' : 'Corregir Mis Datos',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isLocked
                          ? (isDark ? const Color(0xFF450A0A) : Colors.red.shade50)
                          : (isDark ? const Color(0xFF1E293B) : Colors.blue.shade50),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isLocked ? Colors.red.shade400 : Colors.blue.shade200,
                      ),
                    ),
                    child: Text(
                      isLocked
                          ? '🔒 Límite de 3 intentos alcanzado.\n\nPara evitar suplantaciones o cuentas duplicadas, debes solicitar autorización a la Administración o pedirle al Administrador que modifique tus datos desde su panel.'
                          : 'ℹ️ Tienes $remaining intento(s) restante(s) para corregir tu nombre o dirección (Intento ${attempts + 1} de 3).\n\nVerifica escribir las calles y números correctamente.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isLocked
                            ? (isDark ? Colors.red.shade200 : Colors.red.shade900)
                            : (isDark ? const Color(0xFF93C5FD) : AppColors.brandNavy),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: firstCtrl,
                    enabled: !isLocked,
                    decoration: const InputDecoration(
                      labelText: 'Nombre(s) *',
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: l1Ctrl,
                    enabled: !isLocked,
                    decoration: const InputDecoration(
                      labelText: 'Primer Apellido (Paterno) *',
                      prefixIcon: Icon(Icons.badge),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: l2Ctrl,
                    enabled: !isLocked,
                    decoration: const InputDecoration(
                      labelText: 'Segundo Apellido (Materno) *',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: addrCtrl,
                    enabled: !isLocked,
                    decoration: const InputDecoration(
                      labelText: 'Calle / Pasaje / Avenida *',
                      prefixIcon: Icon(Icons.location_on),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: houseCtrl,
                    enabled: !isLocked,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Número de Casa *',
                      prefixIcon: Icon(Icons.home),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cerrar'),
              ),
              if (isLocked)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
                  onPressed: () async {
                    Navigator.pop(dialogCtx);
                    final wpNumber = await service.getAdminWhatsApp();
                    final cleanPhone = wpNumber.replaceAll(RegExp(r'[^0-9]'), '');
                    final msg = Uri.encodeComponent(
                      'Hola Administrador, soy ${service.fullName} de ${service.fullAddress}. He agotado mis 3 intentos de corrección de datos en la app Alerta Vecinal y solicito que me habilites nuevos intentos o me ayudes a modificar mi dirección.',
                    );
                    final uri = Uri.parse('https://wa.me/$cleanPhone?text=$msg');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.chat, size: 16),
                  label: const Text('Pedir Permiso al Admin'),
                )
              else
                ElevatedButton(
                  onPressed: () async {
                    final fName = firstCtrl.text.trim();
                    final l1 = l1Ctrl.text.trim();
                    final l2 = l2Ctrl.text.trim();
                    final addr = addrCtrl.text.trim();
                    final numC = houseCtrl.text.trim();

                    if (fName.isEmpty || l1.isEmpty || l2.isEmpty || addr.isEmpty || numC.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Por favor completa todos los campos obligatorios.')),
                      );
                      return;
                    }

                    final (ok, msg) = await service.updateNeighborProfile(
                      firstName: fName,
                      lastName1: l1,
                      lastName2: l2,
                      address: addr,
                      houseNumber: numC,
                    );

                    if (!ctx.mounted) return;
                    if (ok) {
                      Navigator.pop(dialogCtx);
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppColors.sageGreen,
                          content: Text(msg),
                        ),
                      );
                    } else {
                      showDialog(
                        context: ctx,
                        builder: (errCtx) => AlertDialog(
                          title: const Row(
                            children: [
                              Icon(Icons.warning_amber, color: Colors.orange),
                              SizedBox(width: 8),
                              Text('No se pudo guardar'),
                            ],
                          ),
                          content: Text(msg),
                          actions: [
                            ElevatedButton(
                              onPressed: () => Navigator.pop(errCtx),
                              child: const Text('Entendido'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                  child: const Text('Guardar Corrección'),
                ),
            ],
          );
        },
      ),
    );
  }

  void _handleLogoTap() async {
    if (service.isAdmin) {
      _openAdmin();
      return;
    }

    // Intentar acceso biométrico (huella dactilar) primero
    final canBio = await BiometricService.canAuthenticate();
    if (canBio) {
      final authenticated = await BiometricService.authenticate(
        reason: 'Usa tu huella dactilar para acceder al Panel Administrador',
      );
      if (authenticated) {
        final ok = await service.loginAsAdmin('', biometricOverride: true);
        if (!mounted) return;
        if (ok) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppColors.brandNavy,
              content: Text('¡Huella reconocida! Modo Administrador habilitado.'),
            ),
          );
          _openAdmin();
          return;
        }
      }
    }

    // Fallback: Diálogo con PIN y botón para reintentar huella
    _promptAdminPin();
  }

  void _promptAdminPin() async {
    final pinCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.shield, color: AppColors.brandNavyOf(ctx)),
            const SizedBox(width: 8),
            const Text('Acceso Administrador'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Usa tu huella dactilar o ingresa el PIN de seguridad del administrador:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            Center(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brandNavyOf(ctx),
                  side: BorderSide(color: AppColors.brandNavyOf(ctx)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () async {
                  final bioOk = await BiometricService.authenticate(
                    reason: 'Confirma tu huella para entrar como Administrador',
                  );
                  if (bioOk) {
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx, true);
                    final logged = await service.loginAsAdmin('', biometricOverride: true);
                    if (logged && mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: AppColors.brandNavy,
                          content: Text('¡Autenticado con huella dactilar!'),
                        ),
                      );
                      _openAdmin();
                    }
                  }
                },
                icon: const Icon(Icons.fingerprint, size: 22),
                label: const Text('Ingresar con Huella'),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'O escribe tu PIN de Administrador',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Acceder'),
          ),
        ],
      ),
    );

    if (ok == true && pinCtrl.text.isNotEmpty) {
      final valid = await service.loginAsAdmin(pinCtrl.text.trim());
      if (!mounted) return;
      if (valid) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.brandNavy,
            content: Text('¡Modo Administrador activado!'),
          ),
        );
        _openAdmin();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: const Text('PIN de Administrador incorrecto.'),
          ),
        );
      }
    }
  }

  void _sharePhotosViaWhatsApp() async {
    if (photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay fotos capturadas para enviar.')),
      );
      return;
    }

    final wpNumber = await service.getAdminWhatsApp();
    final cleanPhone = wpNumber.replaceAll(RegExp(r'[^0-9]'), '');

    final currentAlert = service.currentAlert;
    final now = DateTime.now();
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(now);
    final code = currentAlert?.reportCode.isNotEmpty == true
        ? currentAlert!.reportCode
        : '#REP-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final alertType = currentAlert?.type ?? 'EMERGENCIA COMUNITARIA';
    final desc = (currentAlert?.notes.isNotEmpty == true) ? currentAlert!.notes : 'Evidencia registrada por residente';
    final coords = (currentAlert?.latitude != null && currentAlert?.longitude != null)
        ? '${currentAlert?.latitude}, ${currentAlert?.longitude}'
        : (currentAlert?.customLocation.isNotEmpty == true ? currentAlert!.customLocation : service.fullAddress);

    final photosCount = photos.length;
    final filesToShare = List<XFile>.from(photos);
    final paths = filesToShare.map((f) => f.path).toList();

    // 1. Guardar localmente y subir a la nube para que el Admin las tenga al instante sin duplicados
    for (final p in paths) {
      await service.addReportPhoto(code, p);
      if (currentAlert?.id != null) {
        await service.addReportPhoto(currentAlert!.id, p);
      }
    }
    service.uploadReportPhotosCloud(code, paths);

    final cleanCode = code.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    final syncLink = 'https://alerta-vecinal.web.app/reporte?id=$cleanCode';

    final text = '🚨 *EVIDENCIA DE EMERGENCIA VECINAL* 🚨\n'
        '━━━━━━━━━━━━━━━━━━━━━\n'
        '📋 *Reporte:* $code\n'
        '⏰ *Fecha:* $dateStr\n'
        '⚠️ *Tipo:* $alertType\n'
        '👤 *Vecino Emisor:* ${service.fullName}\n'
        '🏠 *Dirección:* ${service.fullAddress}\n'
        '📍 *Ubicación / Coords:* $coords\n'
        '📝 *Detalle:* $desc\n'
        '📸 *Fotos Registradas:* $photosCount foto(s)\n'
        '━━━━━━━━━━━━━━━━━━━━━\n'
        '🔗 *Link Carga Automática al Reporte:* $syncLink\n\n'
        '_Las fotografías ya fueron sincronizadas en el sistema para que se agreguen automáticamente a la Ficha Policial del reporte sin duplicados._';

    // 2. Limpiar inmediatamente la lista de fotos para que la app se actualice
    // y el vecino o vecina no se confunda pensando que quedaron pendientes
    setState(() {
      photos.clear();
    });

    if (cleanPhone.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: cleanPhone));
    }

    if (!mounted) return;

    bool sentDirect = false;
    if (cleanPhone.isNotEmpty) {
      sentDirect = await NativeAlertService.shareWhatsAppDirect(
        phone: cleanPhone,
        text: text,
        imagePaths: paths,
      );
    }

    if (!sentDirect) {
      // Fallback a SharePlus si falla el intent directo
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: filesToShare,
            text: text,
            subject: '🚨 Evidencia Alerta Vecinal - $code',
          ),
        );
      } catch (_) {
        if (cleanPhone.isNotEmpty) {
          final waUri = Uri.parse('whatsapp://send?phone=$cleanPhone&text=${Uri.encodeComponent(text)}');
          final webUri = Uri.parse('https://wa.me/$cleanPhone?text=${Uri.encodeComponent(text)}');
          try {
            if (await canLaunchUrl(waUri)) {
              await launchUrl(waUri, mode: LaunchMode.externalApplication);
            } else {
              await launchUrl(webUri, mode: LaunchMode.externalApplication);
            }
          } catch (_) {}
        }
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sentDirect
                      ? '¡Abriendo chat de WhatsApp del Administrador con las fotos y el reporte listo para enviar!'
                      : (cleanPhone.isNotEmpty
                          ? '¡$photosCount foto(s) listas con el reporte abajo! Selecciona WhatsApp para enviar al Administrador (Tel: +$cleanPhone copiado).'
                          : '¡$photosCount foto(s) preparadas con el reporte abajo! Selecciona la app para enviar.'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _showHelpGuide() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.menu_book, color: AppColors.brandNavyOf(ctx)),
            const SizedBox(width: 8),
            const Text('Guía para Vecinos'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Pasos sencillos para usar tu alarma comunitaria:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 12),
              _buildGuideItem(ctx, '🔴', 'Botón Rojo (Robo):', 'Tócalo si ves un sospechoso o intento de robo en alguna casa.'),
              _buildGuideItem(ctx, '🟠', 'Botón Naranja (Incendio):', 'Tócalo si ves fuego, humo espeso o peligro de incendio.'),
              _buildGuideItem(ctx, '🔵', 'Botón Azul (Médico):', 'Tócalo si alguien necesita auxilio médico o ambulancia urgente.'),
              const Divider(height: 20),
              _buildGuideItem(ctx, '🔊', 'Si suena la alarma en tu teléfono:', 'Mira quién avisa y su casa. Toca "ABRIR EN GOOGLE MAPS" para ver la ubicación.'),
              _buildGuideItem(ctx, '⚠️', 'Regla de Oro:', 'Si estás solo(a), ¡NO salgas a enfrentar delincuentes! Espera que lleguen más vecinos y la policía.'),
              _buildGuideItem(ctx, '📷', 'Fotos de evidencia:', 'Puedes sacar fotos seguras y enviarlas al Administrador por WhatsApp.'),
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              ManualPdfService.exportNeighborManual();
            },
            icon: const Icon(Icons.picture_as_pdf, size: 16),
            label: const Text('Manual en PDF', style: TextStyle(fontSize: 12)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideItem(BuildContext ctx, String emoji, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(desc, style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(ctx), height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openAdmin() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const AdminScreen()),
  );

  void _openHistory() => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: service.reports(),
        builder: (_, s) => SizedBox(
          height: 500,
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.of(sheetCtx).padding.bottom),
            children: [
              Text(
                'Historial de reportes',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimaryOf(sheetCtx),
                ),
              ),
              const SizedBox(height: 10),
              if ((s.data ?? []).isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      'No hay reportes registrados aún.',
                      style: TextStyle(color: AppColors.textSecondaryOf(sheetCtx)),
                    ),
                  ),
                )
              else
                ...(s.data ?? []).map(
                  (r) => ListTile(
                    leading: const Icon(Icons.warning_amber_rounded, color: AppColors.alertCrimson),
                    title: Text(
                      '${r['tipo'] ?? 'Reporte'}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimaryOf(sheetCtx),
                      ),
                    ),
                    subtitle: Text(
                      '${r['emisor'] ?? ''}\n${r['descripcion'] ?? ''}',
                      style: TextStyle(color: AppColors.textSecondaryOf(sheetCtx)),
                    ),
                    isThreeLine: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _callNumber(String number) async {
    final clean = number.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$clean');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo marcar $number: $e')),
        );
      }
    }
  }

  Widget _buildEmergencyCallButton(String number, String label, Color color, IconData icon) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _callNumber(number),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(
                number,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: color),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondaryOf(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _parseColor(String colorHex) {
    try {
      final hex = colorHex.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppColors.alertCrimson;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (alert != null) {
      return ActiveAlertView(
        alert: alert!,
        onDismissLocal: () {
          if (alert != null) {
            final key = service.getAlertKey(alert!);
            service.markAlertDismissed(key);
          }
          setState(() => alert = null);
        },
      );
    }

    final list = buttons.isEmpty ? AlarmSyncService.defaults : buttons;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            // LOGO DIRECTAMENTE TOCABLE (Huella dactilar o PIN)
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _handleLogoTap,
              child: Tooltip(
                message: service.isAdmin ? 'Abrir Panel Admin' : 'Ingresar como Admin (Huella / PIN)',
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/icon.png',
                    width: 38,
                    height: 38,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.shield,
                      size: 32,
                      color: AppColors.brandNavyOf(context),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: _handleLogoTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Alerta Vecinal',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      service.fullAddress.isNotEmpty
                          ? service.fullAddress
                          : (service.neighborName.isNotEmpty ? service.neighborName : 'Comunidad'),
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (service.isAdmin) ...[
            IconButton(
              tooltip: 'Ver como Vecino (Cerrar sesión Admin)',
              icon: const Icon(Icons.person_outline),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Row(
                      children: [
                        Icon(Icons.person_outline, color: AppColors.steelBlue),
                        const SizedBox(width: 8),
                        const Text('Cambiar a Modo Vecino'),
                      ],
                    ),
                    content: const Text(
                      '¿Deseas cerrar la sesión de Administrador y ver la app como Vecino con tus datos registrados?\n\nPodrás volver al Modo Administrador en cualquier momento tocando el logo o desde Configuración con tu huella dactilar o PIN.',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandNavyOf(ctx),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Ver como Vecino'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await service.logoutAdmin();
                  if (!context.mounted) return;
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppColors.brandNavy,
                      content: Text('Sesión de administrador cerrada. Ahora estás viendo la app como Vecino.'),
                    ),
                  );
                }
              },
            ),
            IconButton(
              tooltip: 'Panel Administrador',
              onPressed: _openAdmin,
              icon: const Icon(Icons.shield_outlined),
            ),
            IconButton(
              tooltip: 'Historial',
              onPressed: _openHistory,
              icon: const Icon(Icons.history),
            ),
          ],
          IconButton(
            tooltip: 'Configuración del Dispositivo',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Theme.of(context).cardColor,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => const SettingsSheet(),
            ).then((_) {
              _checkBattery();
              if (mounted) setState(() {});
            }),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              await service.reconnect();
              await _checkBattery();
              await _loadSeguridadPhone();
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 110 + MediaQuery.of(context).padding.bottom),
              children: [
                // Notificación Automática de Actualización OTA (Sin necesidad de escanear QR)
                StreamBuilder<Map<String, dynamic>?>(
                  stream: service.appUpdateStream,
                  builder: (context, snap) {
                    final update = snap.data;
                    if (update == null || update.isEmpty) return const SizedBox.shrink();
                    final remoteCode = (update['versionCode'] is num) ? (update['versionCode'] as num).toInt() : 0;
                    if (remoteCode <= AlarmSyncService.currentVersionCode) return const SizedBox.shrink();
                    if (service.isUpdateDismissed(remoteCode)) return const SizedBox.shrink();

                    final isDark = Theme.of(context).brightness == Brightness.dark;
                    final verName = update['versionName'] ?? 'Nueva Versión';
                    final notes = update['notes'] ?? 'Mejoras y optimizaciones del sistema.';
                    final downloadUrl = update['downloadUrl'] ?? '';

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 12),
                      color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: Color(0xFF10B981), width: 1.8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.system_update, color: Color(0xFF059669), size: 26),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '¡NUEVA ACTUALIZACIÓN DISPONIBLE ($verName)!',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w900,
                                      color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 20),
                                  color: isDark ? Colors.white70 : const Color(0xFF047857),
                                  tooltip: 'Ocultar notificación',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () async {
                                    await service.dismissUpdate(remoteCode);
                                    if (context.mounted) setState(() {});
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              notes,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : const Color(0xFF047857),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF059669),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () async {
                                  await service.dismissUpdate(remoteCode);
                                  if (context.mounted) setState(() {});
                                  if (downloadUrl.isNotEmpty) {
                                    final directUrl = AlarmSyncService.convertDriveToDirectDownload(downloadUrl);
                                    final uri = Uri.parse(directUrl);
                                    try {
                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(this.context).showSnackBar(
                                          SnackBar(content: Text('Error abriendo enlace: $e')),
                                        );
                                      }
                                    }
                                  }
                                },
                                icon: const Icon(Icons.download, size: 20),
                                label: const Text(
                                  'ACTUALIZAR AHORA (Sin Código QR)',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

            // Guía Rápida para Vecinos y Adultos Mayores
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: ThemeService().isDarkMode ? const Color(0xFF1E293B) : Colors.blue.shade50,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.menu_book, color: AppColors.steelBlue, size: 26),
                title: Text(
                  '¿Cómo usar la aplicación? (Guía Rápida)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                subtitle: Text(
                  'Instrucciones sencillas con letra grande para vecinos y adultos mayores.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, color: AppColors.steelBlue),
                onTap: _showHelpGuide,
              ),
            ),

            // Banner de optimización de batería (para que suene bloqueado)
            if (!_isIgnoringBattery)
              Card(
                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF33230A) : Colors.amber.shade100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.amber.shade700 : Colors.amber.shade300,
                  ),
                ),
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.battery_alert, color: Colors.deepOrange),
                  title: Text(
                    'Optimización de batería activa',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.amber.shade200 : Colors.brown.shade900,
                    ),
                  ),
                  subtitle: Text(
                    'Para que la alarma suene con la pantalla apagada, activa este permiso.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.amber.shade100 : Colors.brown.shade800,
                    ),
                  ),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: () async {
                      await NativeAlertService.requestIgnoreBatteryOptimizations();
                      await Future.delayed(const Duration(seconds: 1));
                      _checkBattery();
                    },
                    child: const Text('ACTIVAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),

            // Tablón de Comunicados Oficiales de la Administración (Avisos Comunitarios sin sirena)
            StreamBuilder<Map<String, dynamic>?>(
              stream: service.communityNoticeStream,
              builder: (context, snap) {
                final notice = snap.data;
                if (notice == null || notice.isEmpty) return const SizedBox.shrink();
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                  ),
                  color: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.campaign, color: Color(0xFF6366F1), size: 24),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'COMUNICADO OFICIAL DE LA VILLA',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
                                  color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4338CA),
                                ),
                              ),
                            ),
                            if (notice['fecha'] != null)
                              Text(
                                '${notice['fecha']}',
                                style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${notice['titulo'] ?? 'Aviso Comunitario'}',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${notice['mensaje'] ?? ''}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondaryOf(context),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            // Tarjeta de Identidad y Conexión del Vecino (clickeable para corregir datos)
            StreamBuilder<bool>(
              stream: service.connectionStream,
              initialData: service.isConnected,
              builder: (_, s) {
                final isOnline = s.data == true;
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _showEditProfileDialog,
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: service.isAdmin
                                  ? (isDark ? const Color(0xFF312E81) : Colors.indigo.shade50)
                                  : (isDark ? const Color(0xFF064E3B) : Colors.teal.shade50),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              service.isAdmin ? Icons.admin_panel_settings : Icons.home,
                              color: service.isAdmin
                                  ? (isDark ? const Color(0xFFA5B4FC) : AppColors.brandNavy)
                                  : (isDark ? const Color(0xFF6EE7B7) : AppColors.sageGreen),
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isOnline ? AppColors.sageGreen : AppColors.amberWarning,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: isOnline ? null : () {
                                        service.reconnect();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Reconectando con el servidor Firebase...'),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      },
                                      child: Text(
                                        isOnline ? 'EN LÍNEA • PROTEGIDO' : 'CONECTANDO... (Toca para reintentar)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isOnline ? AppColors.sageGreen : AppColors.amberWarning,
                                        ),
                                      ),
                                    ),
                                    if (service.isAdmin) ...[
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF2563EB) : AppColors.brandNavy,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'ADMIN',
                                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  service.fullName.isNotEmpty ? service.fullName : service.neighborName,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                                ),
                                if (service.fullAddress.isNotEmpty)
                                  Text(
                                    service.fullAddress,
                                    style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Corregir mis datos (3 intentos permitidos)',
                            child: IconButton(
                              icon: const Icon(Icons.edit_note, color: AppColors.steelBlue, size: 26),
                              onPressed: _showEditProfileDialog,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 12),

            // Botonera de Centrales de Emergencia (Discado Rápido a 1-Toque)
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.phone_in_talk, size: 18, color: Colors.redAccent),
                        const SizedBox(width: 8),
                        Text(
                          'CENTRALES DE EMERGENCIA (1-TOQUE)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _buildEmergencyCallButton('133', 'Carabineros', Colors.green.shade700, Icons.local_police),
                        const SizedBox(width: 8),
                        _buildEmergencyCallButton('132', 'Bomberos', Colors.red.shade700, Icons.fire_truck),
                        const SizedBox(width: 8),
                        _buildEmergencyCallButton('131', 'SAMU Ambulancia', Colors.blue.shade700, Icons.medical_services),
                        const SizedBox(width: 8),
                        _buildEmergencyCallButton(_seguridadPhone, 'Seguridad', Colors.indigo.shade700, Icons.shield),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Encabezado de Botones de Emergencia
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
              child: Text(
                'BOTONES DE ALERTA RÁPIDA',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : AppColors.textMuted,
                ),
              ),
            ),

            // Lista de Botones de Alarma (por defecto + creados por Admin)
            ...list.map(
              (b) {
                final btnColor = _parseColor(b.color);
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _send(b),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Text(b.icon, style: const TextStyle(fontSize: 32)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.title,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  b.subtitle,
                                  style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: btnColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () => _send(b),
                            child: const Text(
                              'ACTIVAR',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            // Sección de Fotos / Evidencia Fotográfica
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.camera_alt,
                              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF93C5FD) : AppColors.brandNavy,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Evidencia Fotográfica',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimaryOf(context),
                              ),
                            ),
                          ],
                        ),
                        if (photos.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? const Color(0xFF1E3A8A)
                                      : AppColors.brandNavy.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${photos.length} ${photos.length == 1 ? 'foto' : 'fotos'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.brandNavy,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => setState(() => photos.clear()),
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.delete_sweep, size: 15, color: Colors.red),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Limpiar',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.red.shade400,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Captura fotos de vehículos, personas o situaciones sospechosas para respaldo vecinal.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF93C5FD) : AppColors.brandNavy,
                              side: BorderSide(
                                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF93C5FD) : AppColors.brandNavy,
                              ),
                            ),
                            onPressed: () => _pickPhoto(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt_outlined, size: 18),
                            label: const Text('Tomar Foto', style: TextStyle(fontSize: 13)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFE2E8F0) : AppColors.brandNavy,
                              side: BorderSide(
                                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF475569) : AppColors.borderSubtle,
                              ),
                            ),
                            onPressed: () => _pickPhoto(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined, size: 18),
                            label: const Text('Galería', style: TextStyle(fontSize: 13)),
                          ),
                        ),
                      ],
                    ),
                    if (photos.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 90,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: photos.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (ctx, i) {
                            final photo = photos[i];
                            return Stack(
                              children: [
                                GestureDetector(
                                  onTap: () => _previewPhoto(photo, i),
                                  child: Container(
                                    width: 90,
                                    height: 90,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF475569) : AppColors.borderSubtle,
                                      ),
                                      image: DecorationImage(
                                        image: FileImage(File(photo.path)),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: () => setState(() => photos.removeAt(i)),
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Botón para enviar las fotos al Admin por WhatsApp
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366), // WhatsApp Green
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _sharePhotosViaWhatsApp,
                          icon: const Icon(Icons.send, size: 18),
                          label: const Text(
                            'Enviar Evidencia al Admin (WhatsApp)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      // Botón Flotante Guía para Vecinos en Esquina Inferior Izquierda (Margen seguro barra navegación Android)
      Positioned(
        left: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
        child: Material(
          elevation: 4,
          shadowColor: Colors.black38,
          borderRadius: BorderRadius.circular(24),
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1E293B)
              : Colors.white,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: _showHelpGuide,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF475569)
                      : const Color(0xFFCBD5E1),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.menu_book_rounded, color: AppColors.steelBlue, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Guía Vecinos',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  ),
);
  }
}
