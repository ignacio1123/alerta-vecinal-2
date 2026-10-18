import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alert_model.dart';
import 'alarm_player_service.dart';
import 'native_alert_service.dart';

@pragma('vm:entry-point')
void startForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(AlertTaskHandler());
}

class AlertTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) async {
    // Sondeo de seguridad en segundo plano cada 3.5 segundos
    // Permite detectar alertas incluso si el socket de Firebase entró en reposo por Doze Mode
    try {
      final url = Uri.parse('https://alerta-vecinal-coronel-default-rtdb.firebaseio.com/emergenciaActual.json');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && res.body.isNotEmpty && res.body != 'null') {
        final data = jsonDecode(res.body);
        if (data is Map && data['tipo'] != null) {
          final tipo = data['tipo'].toString();
          final emisor = (data['emisor'] ?? 'Vecino').toString();
          final desc = (data['descripcion'] ?? '').toString();
          final rawTs = data['timestamp'];
          int? ts;
          if (rawTs is int) ts = rawTs;
          if (rawTs is String) ts = int.tryParse(rawTs);

          // Comprobar que la emergencia no tenga más de 45 min
          final isRecent = ts == null || (DateTime.now().millisecondsSinceEpoch - ts < 45 * 60 * 1000);

          if (isRecent) {
            // Verificar si el usuario no silenció o descartó esta alerta en este equipo
            final prefs = await SharedPreferences.getInstance();
            final lastSilenced = prefs.getString('last_silenced_alert_id');
            final lastDismissed = prefs.getString('last_dismissed_alert_id');
            final alertKey = (data['codigoReporte'] ?? data['reportCode'] ?? '${data['id']}_$ts').toString();

            if (lastSilenced != alertKey && lastDismissed != alertKey) {
              FlutterForegroundTask.wakeUpScreen();
              FlutterForegroundTask.updateService(
                notificationTitle: '🚨 ¡ALERTA VECINAL: $tipo!',
                notificationText: '$emisor: $desc'.trim(),
              );
              FlutterForegroundTask.launchApp();
              await AlarmPlayerService().startAlarm(tipo);
            }
          }

          FlutterForegroundTask.sendDataToMain(data);
        } else {
          await AlarmPlayerService().stopAlarm();
        }
      } else {
        await AlarmPlayerService().stopAlarm();
      }
    } catch (_) {}
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await AlarmPlayerService().stopAlarm();
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }
}

class EmergencyButton {
  final String id, title, subtitle, icon;
  final bool requiresDescription;
  final bool allowsPhotos;
  final String color;

  const EmergencyButton({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.requiresDescription,
    this.allowsPhotos = true,
    required this.color,
  });

  factory EmergencyButton.fromMap(String id, Map<dynamic, dynamic> m) => EmergencyButton(
    id: id,
    title: '${m['titulo'] ?? m['title'] ?? 'Emergencia'}',
    subtitle: '${m['subtitulo'] ?? m['subtitle'] ?? ''}',
    icon: '${m['icono'] ?? m['icon'] ?? '🚨'}',
    requiresDescription: m['requiereDesc'] == true || m['requiresDescription'] == true,
    allowsPhotos: m['permiteFotos'] != false && m['allowsPhotos'] != false,
    color: '${m['color'] ?? '#D32F2F'}',
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'titulo': title,
    'subtitulo': subtitle,
    'icono': icon,
    'requiereDesc': requiresDescription,
    'permiteFotos': allowsPhotos,
    'color': color,
  };
}

class AlarmSyncService {
  static final AlarmSyncService _instance = AlarmSyncService._internal();
  factory AlarmSyncService() => _instance;
  AlarmSyncService._internal();

  final _db = FirebaseDatabase.instance;
  final _alerts = StreamController<AlertModel?>.broadcast();
  final _connection = StreamController<bool>.broadcast();
  final _buttons = StreamController<List<EmergencyButton>>.broadcast();
  Stream<AlertModel?> get alertStream => _alerts.stream;
  Stream<bool> get connectionStream => _connection.stream;
  Stream<List<EmergencyButton>> get buttonsStream => _buttons.stream;
  AlertModel? currentAlert;
  bool isConnected = false;
  bool isRegistered = false;
  bool isAdmin = false;
  String firstName = '';
  String lastName1 = '';
  String lastName2 = '';
  String region = 'Región del Biobío';
  String comuna = 'Coronel';
  String sector = 'Villa Escuadrón Galilea';
  String address = '';
  String houseNumber = '';
  String phone = '';
  String pin = '';
  String fullName = '';
  String fullAddress = '';
  String neighborName = 'Sin registrar';
  String get serverUrl => 'Firebase Realtime Database';
  String? neighborId;
  List<EmergencyButton> buttons = const [];

  String? _lastDismissedAlertId;
  String? _lastSilencedAlertId;
  String? _lastSoundedAlertId;

  String getAlertKey(AlertModel alert) {
    if (alert.reportCode.isNotEmpty) return alert.reportCode;
    return '${alert.id}_${alert.timestamp.millisecondsSinceEpoch}';
  }

  bool isAlertDismissed(String alertKey) => _lastDismissedAlertId == alertKey;
  bool isAlertSilenced(String alertKey) => _lastSilencedAlertId == alertKey;

  Future<void> markAlertDismissed(String alertKey) async {
    _lastDismissedAlertId = alertKey;
    currentAlert = null;
    _alerts.add(null);
    await AlarmPlayerService().stopAlarm();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_dismissed_alert_id', alertKey);
    } catch (_) {}
  }

  Future<void> markAlertSilenced(String alertKey) async {
    _lastSilencedAlertId = alertKey;
    await AlarmPlayerService().stopAlarm();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_silenced_alert_id', alertKey);
    } catch (_) {}
  }

  Future<void> _persistLastSoundedAlert(String alertKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_sounded_alert_id', alertKey);
    } catch (_) {}
  }

  static const defaults = [
    EmergencyButton(id: '1', title: 'ROBO / INTRUSIÓN', subtitle: 'Intruso en la propiedad', icon: '🕵️', requiresDescription: false, allowsPhotos: true, color: '#D32F2F'),
    EmergencyButton(id: '2', title: 'INCENDIO', subtitle: 'Fuego o humo visible', icon: '🔥', requiresDescription: false, allowsPhotos: true, color: '#F57C00'),
    EmergencyButton(id: '3', title: 'ACCIDENTE MÉDICO', subtitle: 'Requiere asistencia', icon: '🚑', requiresDescription: false, allowsPhotos: true, color: '#1976D2'),
  ];

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    isRegistered = prefs.getBool('is_registered') ?? false;
    isAdmin = prefs.getBool('is_admin') ?? false;
    firstName = prefs.getString('first_name') ?? '';
    lastName1 = prefs.getString('last_name1') ?? '';
    lastName2 = prefs.getString('last_name2') ?? '';
    region = prefs.getString('region') ?? 'Región del Biobío';
    comuna = prefs.getString('comuna') ?? 'Coronel';
    sector = prefs.getString('sector') ?? 'Villa Escuadrón Galilea';
    address = prefs.getString('address') ?? '';
    houseNumber = prefs.getString('house_number') ?? '';
    phone = prefs.getString('phone') ?? '';
    pin = prefs.getString('pin') ?? '';
    fullName = prefs.getString('full_name') ?? '';
    fullAddress = prefs.getString('full_address') ?? '';
    neighborName = prefs.getString('neighbor_name') ?? (fullName.isNotEmpty ? '$fullName ($fullAddress)' : 'Sin registrar');
    neighborId = prefs.getString('neighbor_id');
    _lastDismissedAlertId = prefs.getString('last_dismissed_alert_id');
    _lastSilencedAlertId = prefs.getString('last_silenced_alert_id');
    _lastSoundedAlertId = prefs.getString('last_sounded_alert_id');
    _dismissedUpdateVersion = prefs.getInt('dismissed_update_version') ?? 0;
    await AlarmPlayerService().init();

    // Habilitar persistencia local y sincronización continua en caché
    try {
      _db.setPersistenceEnabled(true);
    } catch (e) {
      debugPrint('Firebase Persistence notice: $e');
    }

    try {
      _db.ref('emergenciaActual').keepSynced(true);
      _db.ref('botones').keepSynced(true);
      _db.ref('comunicados/actual').keepSynced(true);
    } catch (e) {
      debugPrint('keepSynced notice: $e');
    }

    // Inicializar y arrancar Foreground Service para mantener viva la app con pantalla bloqueada
    _initForegroundService();
    await _startForegroundService();

    // Escuchar datos del ForegroundTask cuando detecta alertas en segundo plano
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);

    try {
      await FirebaseAuth.instance.signInAnonymously();
      isConnected = true;
      _connection.add(true);
    } catch (e) {
      debugPrint('Firebase Auth: $e');
      _connection.add(false);
    }
    _listen();
  }

  void _onReceiveTaskData(dynamic data) {
    if (data is Map && data['tipo'] != null) {
      debugPrint('Alerta recibida desde segundo plano (ForegroundTask): $data');
      _processIncomingAlertData('foreground_task', Map<dynamic, dynamic>.from(data));
    }
  }

  void _initForegroundService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'alerta_vecinal_emergency_v4',
        channelName: '🚨 Alerta Vecinal Comunitaria',
        channelDescription: 'Canal prioritario de máxima urgencia para robo, incendio y emergencias médicas',
        channelImportance: NotificationChannelImportance.MAX,
        priority: NotificationPriority.MAX,
        enableVibration: true,
        playSound: true,
        onlyAlertOnce: false,
        showWhen: true,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(3500),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: true,
      ),
    );
  }

  Future<void> _startForegroundService() async {
    if (!Platform.isAndroid) return;
    try {
      final notificationPermission = await FlutterForegroundTask.checkNotificationPermission();
      if (notificationPermission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.restartService();
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 101,
          serviceTypes: [
            ForegroundServiceTypes.dataSync,
            ForegroundServiceTypes.remoteMessaging,
          ],
          notificationTitle: '🚨 Vigilancia Vecinal Activa',
          notificationText: 'Conectado a la red de emergencia vecinal.',
          notificationInitialRoute: '/',
          callback: startForegroundTaskCallback,
        );
      }
    } catch (e) {
      debugPrint('Error iniciando Foreground Service: $e');
    }
  }

  Timer? _heartbeatTimer;

  void _processIncomingAlertData(String key, dynamic value) {
    if (value is Map && value['tipo'] != null) {
      final alert = AlertModel.fromMap(key, value);
      final alertKey = getAlertKey(alert);
      final ageInMinutes = DateTime.now().difference(alert.timestamp).inMinutes.abs();

      // 1. Caducidad: Si la alerta tiene 45 minutos o más de antigüedad, es una alarma caducada
      if (ageInMinutes >= 45) {
        debugPrint('Alerta anterior caducada ($ageInMinutes min transcurridos): se descarta sirena.');
        if (ageInMinutes >= 60) {
          _db.ref('emergenciaActual').remove().catchError((_) {});
        }
        currentAlert = null;
        _alerts.add(null);
        AlarmPlayerService().stopAlarm();
        return;
      }

      // 2. Si el usuario ya cerró/descartó esta alerta previamente en este dispositivo
      if (isAlertDismissed(alertKey)) {
        debugPrint('Alerta $alertKey ya fue descartada en este dispositivo.');
        currentAlert = null;
        _alerts.add(null);
        AlarmPlayerService().stopAlarm();
        return;
      }

      currentAlert = alert;
      _alerts.add(alert);

      // 3. Comprobar si ya fue silenciada en este equipo por el usuario
      final alreadySilenced = isAlertSilenced(alertKey);
      final alreadySounded = (_lastSoundedAlertId == alertKey);

      if (!alreadySilenced) {
        if (!alreadySounded || !AlarmPlayerService().isPlaying) {
          _lastSoundedAlertId = alertKey;
          _persistLastSoundedAlert(alertKey);
          AlarmPlayerService().startAlarm(alert.type);
        }

        if (Platform.isAndroid) {
          FlutterForegroundTask.updateService(
            notificationTitle: '🚨 ¡ALERTA VECINAL: ${alert.type}!',
            notificationText: 'Vecino: ${alert.sender} ${alert.description}'.trim(),
          );
          FlutterForegroundTask.launchApp();
        }
      } else {
        debugPrint('Alerta ($alertKey) ya fue silenciada por el usuario en este equipo.');
      }
    } else {
      currentAlert = null;
      _alerts.add(null);
      AlarmPlayerService().stopAlarm();

      if (Platform.isAndroid) {
        FlutterForegroundTask.updateService(
          notificationTitle: '🚨 Vigilancia Vecinal Activa',
          notificationText: 'Sistema conectado y red vecinal protegida.',
        );
      }
    }
  }

  void _listen() {
    _db.ref('emergenciaActual').onValue.listen((event) {
      final value = event.snapshot.value;
      _processIncomingAlertData(event.snapshot.key ?? 'active', value);
    }, onError: (_) => _connection.add(false));

    // Heartbeat periódico: Si la conexión WebSocket cayó por reposo del sistema, forzar reactivación
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!isConnected) {
        debugPrint('Heartbeat: Reintentando reconexión activa a Firebase Realtime Database');
        _db.goOnline();
      }
    });

    void listenButtons(String path) {
      _db.ref(path).onValue.listen((event) {
        final value = event.snapshot.value;
        if (value is Map && value.isNotEmpty) {
          final customList = value.entries
              .map((e) => EmergencyButton.fromMap('${e.key}', Map<dynamic, dynamic>.from(e.value as Map)))
              .toList();

          final hasDefaults = customList.any((b) => b.title == 'ROBO / INTRUSIÓN');
          if (hasDefaults) {
            buttons = customList;
          } else {
            buttons = [...defaults, ...customList];
          }
          _buttons.add(buttons);
        } else {
          buttons = defaults;
          _buttons.add(buttons);
        }
      });
    }
    listenButtons('botones');

    _db.ref('.info/connected').onValue.listen((e) {
      isConnected = e.snapshot.value == true;
      _connection.add(isConnected);

      if (Platform.isAndroid && currentAlert == null) {
        FlutterForegroundTask.updateService(
          notificationTitle: '🚨 Vigilancia Vecinal Activa',
          notificationText: isConnected
              ? 'En línea y red protegida'
              : 'Reconectando con la base de datos...',
        );
      }
    });

    // Escuchar comunicados oficiales y notificar en el teléfono de los vecinos
    _db.ref('comunicados/actual').onValue.listen((event) async {
      final val = event.snapshot.value;
      if (val is Map) {
        final notice = Map<String, dynamic>.from(val);
        final title = '${notice['titulo'] ?? 'Aviso Comunitario'}'.trim();
        final message = '${notice['mensaje'] ?? ''}'.trim();
        final rawTs = notice['timestamp'];
        final tsStr = rawTs?.toString() ?? '$title-$message';

        try {
          final prefs = await SharedPreferences.getInstance();
          final lastSeen = prefs.getString('last_seen_community_notice');

          if (lastSeen != tsStr && title.isNotEmpty) {
            await prefs.setString('last_seen_community_notice', tsStr);

            await NativeAlertService.showCommunityNotification(
              title: '📢 COMUNICADO OFICIAL: $title',
              message: message,
            );

            if (Platform.isAndroid && currentAlert == null) {
              FlutterForegroundTask.updateService(
                notificationTitle: '📢 Comunicado Oficial: $title',
                notificationText: message,
              );
            }
          }
        } catch (_) {}
      }
    });
  }

  static String normalizeText(String input) {
    var s = input.toLowerCase().trim();
    const from = 'áàäâéèëêíìïîóòöôúùüûñ';
    const to   = 'aaaaeeeeiiiioooouuuun';
    for (int i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static String buildHouseKey(String address, String houseNumber) {
    final a = normalizeText(address).replaceAll(RegExp(r'[^a-z0-9]'), '_');
    final h = normalizeText(houseNumber).replaceAll(RegExp(r'[^a-z0-9]'), '_');
    return '${a}_$h';
  }

  Future<List<Map<String, dynamic>>> getNeighborsInHouse(String address, String houseNumber) async {
    try {
      final snap = await _db.ref('vecinos').get().timeout(const Duration(seconds: 6));
      if (!snap.exists || snap.value is! Map) return [];
      final neighbors = Map<dynamic, dynamic>.from(snap.value as Map);
      final reqAddr = normalizeText(address);
      final reqHouse = normalizeText(houseNumber);

      final List<Map<String, dynamic>> list = [];
      for (final entry in neighbors.entries) {
        final val = entry.value;
        if (val is! Map) continue;
        final map = Map<String, dynamic>.from(val);
        map['id'] = entry.key.toString();

        final existAddr = normalizeText('${map['direccion'] ?? map['calle'] ?? ''}');
        final existHouse = normalizeText('${map['numeroCasa'] ?? map['casa'] ?? ''}');

        if (existHouse == reqHouse) {
          final wordsReq = reqAddr.split(' ').where((w) => w.length > 2).toSet();
          final wordsExist = existAddr.split(' ').where((w) => w.length > 2).toSet();
          final sharesWord = wordsReq.intersection(wordsExist).isNotEmpty ||
              reqAddr.contains(existAddr) ||
              existAddr.contains(reqAddr);
          if (sharesWord) {
            list.add(map);
          }
        }
      }
      return list;
    } catch (e) {
      debugPrint('Error obteniendo vecinos de la vivienda: $e');
      return [];
    }
  }

  Future<int> getHouseDeviceLimit(String address, String houseNumber) async {
    try {
      final key = buildHouseKey(address, houseNumber);
      final snap = await _db.ref('config/casas_cupos/$key/limite').get().timeout(const Duration(seconds: 4));
      if (snap.exists && snap.value is num) {
        final lim = (snap.value as num).toInt();
        if (lim >= 3) return lim;
      }
    } catch (e) {
      debugPrint('Error leyendo límite de dispositivos de la casa: $e');
    }
    return 3; // Plan comunitario estándar: hasta 3 teléfonos incluidos por casa
  }

  Future<void> setHouseDeviceLimit(String address, String houseNumber, int newLimit, {int extraPaidCount = 0}) async {
    final key = buildHouseKey(address, houseNumber);
    await _db.ref('config/casas_cupos/$key').update({
      'limite': newLimit,
      'direccion': address,
      'numeroCasa': houseNumber,
      'extraPaidCount': extraPaidCount,
      'updatedAt': ServerValue.timestamp,
    }).timeout(const Duration(seconds: 6));
  }

  Future<(bool, String?)> checkDuplicateNeighbor({
    required String firstName,
    required String lastName1,
    required String lastName2,
    required String address,
    required String houseNumber,
    String? phone,
    String? excludeId,
  }) async {
    try {
      final snap = await _db.ref('vecinos').get().timeout(const Duration(seconds: 6));
      if (!snap.exists || snap.value is! Map) return (false, null);

      final neighbors = Map<dynamic, dynamic>.from(snap.value as Map);
      final reqFirst = normalizeText(firstName);
      final reqL1 = normalizeText(lastName1);
      final reqL2 = normalizeText(lastName2);
      final reqAddr = normalizeText(address);
      final reqHouse = normalizeText(houseNumber);
      final cleanReqPhone = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');

      int houseCount = 0;

      for (final entry in neighbors.entries) {
        if (excludeId != null && (entry.key == excludeId || (entry.value is Map && (entry.value as Map)['id'] == excludeId))) {
          continue;
        }
        final val = entry.value;
        if (val is! Map) continue;
        final existingFull = normalizeText('${val['nombreCompleto'] ?? '${val['nombre'] ?? ''} ${val['apellido1'] ?? ''} ${val['apellido2'] ?? ''}'}');
        final existFirst = normalizeText('${val['nombre'] ?? ''}');
        final existL1 = normalizeText('${val['apellido1'] ?? ''}');
        final existL2 = normalizeText('${val['apellido2'] ?? ''}');
        final existingAddr = normalizeText('${val['direccion'] ?? val['calle'] ?? ''}');
        final existingHouse = normalizeText('${val['numeroCasa'] ?? val['casa'] ?? ''}');
        final existingPhone = '${val['telefono'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');

        // 1. Teléfono celular duplicado (cada persona debe usar su propio número)
        if (cleanReqPhone.length >= 8 && existingPhone.isNotEmpty && (existingPhone == cleanReqPhone || existingPhone.endsWith(cleanReqPhone))) {
          return (
            true,
            'El teléfono celular ya está vinculado a la cuenta de "$existingFull". Si desinstalaste la app o cambiaste de equipo, usa la pestaña "Ya Estoy Registrado" para ingresar.'
          );
        }

        // 2. Mismo nombre y dos apellidos idénticos (la misma persona no puede duplicarse)
        if (reqFirst == existFirst && reqL1 == existL1 && (reqL2.isEmpty || existL2.isEmpty || reqL2 == existL2)) {
          return (
            true,
            'Ya existe un registro para "$firstName $lastName1 $lastName2" en el sistema. Para restaurar tu acceso tras reinstalar la app, pulsa en "Ya Estoy Registrado".'
          );
        }

        // 3. Contar residentes que comparten la misma vivienda
        if (reqHouse.isNotEmpty && reqHouse == existingHouse) {
          final wordsReqAddr = reqAddr.split(' ').where((w) => w.length > 2).toSet();
          final wordsExistAddr = existingAddr.split(' ').where((w) => w.length > 2).toSet();
          final sharesAddrWord = wordsReqAddr.intersection(wordsExistAddr).isNotEmpty ||
              reqAddr.contains(existingAddr) ||
              existingAddr.contains(reqAddr);
          if (sharesAddrWord) {
            houseCount++;
          }
        }
      }

      // 4. Validación de cupo por vivienda (3 teléfonos estándar, 4° o más exige $5.000)
      final limit = await getHouseDeviceLimit(address, houseNumber);
      if (houseCount >= limit) {
        return (
          true,
          'LIMIT_REACHED::$houseCount::$limit'
        );
      }

      return (false, null);
    } catch (e) {
      debugPrint('Error comprobando duplicados: $e');
      return (false, null);
    }
  }

  Future<Map<String, dynamic>?> findExistingNeighborMatch({
    String? phone,
    String? address,
    String? houseNumber,
    String? firstName,
    String? lastName1,
  }) async {
    try {
      final snap = await _db.ref('vecinos').get().timeout(const Duration(seconds: 6));
      if (!snap.exists || snap.value is! Map) return null;

      final neighbors = Map<dynamic, dynamic>.from(snap.value as Map);
      final cleanPhone = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
      final normFirst = firstName != null ? normalizeText(firstName) : '';
      final normL1 = lastName1 != null ? normalizeText(lastName1) : '';

      for (final entry in neighbors.entries) {
        final val = entry.value;
        if (val is! Map) continue;
        final map = Map<String, dynamic>.from(val);
        map['id'] = entry.key.toString();

        // 1. Coincidencia por teléfono celular (prioridad absoluta)
        if (cleanPhone.length >= 8) {
          final existPhone = '${map['telefono'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
          if (existPhone.isNotEmpty && (existPhone == cleanPhone || existPhone.endsWith(cleanPhone) || cleanPhone.endsWith(existPhone))) {
            return map;
          }
        }

        // 2. Coincidencia por nombre completo idéntico (mismo residente)
        if (normFirst.isNotEmpty && normL1.isNotEmpty) {
          final existFirst = normalizeText('${map['nombre'] ?? ''}');
          final existL1 = normalizeText('${map['apellido1'] ?? ''}');
          if (existFirst == normFirst && existL1 == normL1) {
            return map;
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error buscando coincidencia de vecino: $e');
      return null;
    }
  }

  Future<(bool, String)> restoreNeighborAccount({
    String? phone,
    String? address,
    String? houseNumber,
    required String enteredPin,
  }) async {
    try {
      final snap = await _db.ref('vecinos').get().timeout(const Duration(seconds: 8));
      if (!snap.exists || snap.value is! Map) {
        return (false, 'No se pudo conectar con el padrón de vecinos en la nube. Verifica tu conexión a internet.');
      }
      final neighbors = Map<dynamic, dynamic>.from(snap.value as Map);
      final cleanPhone = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
      final normAddr = address != null ? normalizeText(address) : '';
      final normHouse = houseNumber != null ? normalizeText(houseNumber) : '';

      Map<String, dynamic>? matched;
      String matchedKey = '';

      for (final entry in neighbors.entries) {
        final val = entry.value;
        if (val is! Map) continue;
        final map = Map<String, dynamic>.from(val);

        if (cleanPhone.length >= 8) {
          final existPhone = '${map['telefono'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
          if (existPhone.isNotEmpty && (existPhone == cleanPhone || existPhone.endsWith(cleanPhone) || cleanPhone.endsWith(existPhone))) {
            matched = map;
            matchedKey = entry.key.toString();
            break;
          }
        }

        if (normAddr.isNotEmpty && normHouse.isNotEmpty) {
          final existAddr = normalizeText('${map['direccion'] ?? map['calle'] ?? ''}');
          final existHouse = normalizeText('${map['numeroCasa'] ?? map['casa'] ?? ''}');
          if (existHouse == normHouse && (existAddr == normAddr || existAddr.contains(normAddr) || normAddr.contains(existAddr))) {
            matched = map;
            matchedKey = entry.key.toString();
            break;
          }
        }
      }

      if (matched == null) {
        return (false, 'No encontramos ningún registro con los datos ingresados. Verifica el número de celular o la dirección.');
      }

      final cleanEnteredPin = enteredPin.trim();
      final storedPin = '${matched['pin'] ?? ''}'.trim();

      if (storedPin.isNotEmpty && storedPin != cleanEnteredPin) {
        return (false, 'El PIN de seguridad de 4 dígitos es incorrecto.');
      }

      if (storedPin.isEmpty && cleanEnteredPin.isNotEmpty) {
        try {
          await _db.ref('vecinos/$matchedKey/pin').set(cleanEnteredPin);
        } catch (_) {}
      }

      neighborId = matchedKey;
      firstName = '${matched['nombre'] ?? ''}'.trim();
      lastName1 = '${matched['apellido1'] ?? ''}'.trim();
      lastName2 = '${matched['apellido2'] ?? ''}'.trim();
      region = '${matched['region'] ?? 'Región del Biobío'}'.trim();
      comuna = '${matched['comuna'] ?? 'Coronel'}'.trim();
      sector = '${matched['sector'] ?? 'Villa Escuadrón Galilea'}'.trim();
      address = '${matched['direccion'] ?? matched['calle'] ?? ''}'.trim();
      houseNumber = '${matched['numeroCasa'] ?? matched['casa'] ?? ''}'.trim();
      phone = '${matched['telefono'] ?? cleanPhone}'.trim();
      pin = cleanEnteredPin;
      fullName = '${matched['nombreCompleto'] ?? '$firstName $lastName1 $lastName2'}'.trim();
      fullAddress = '${matched['direccionCompleta'] ?? '$address #$houseNumber'}'.trim();
      isAdmin = matched['rol'] == 'administrador';
      neighborName = isAdmin ? 'ADMIN: $fullName ($fullAddress)' : '$fullName ($fullAddress)';
      isRegistered = true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_registered', true);
      await prefs.setBool('is_admin', isAdmin);
      await prefs.setString('neighbor_id', matchedKey);
      await prefs.setString('first_name', firstName);
      await prefs.setString('last_name1', lastName1);
      await prefs.setString('last_name2', lastName2);
      await prefs.setString('region', region);
      await prefs.setString('comuna', comuna);
      await prefs.setString('sector', sector);
      await prefs.setString('address', address);
      await prefs.setString('house_number', houseNumber);
      await prefs.setString('phone', phone);
      await prefs.setString('pin', pin);
      await prefs.setString('full_name', fullName);
      await prefs.setString('full_address', fullAddress);
      await prefs.setString('neighbor_name', neighborName);

      return (true, '¡Bienvenido(a) de vuelta, $fullName! Tu vivienda ($fullAddress) ha sido vinculada correctamente.');
    } catch (e) {
      debugPrint('Error restaurando cuenta: $e');
      return (false, 'Ocurrió un error al restaurar tu cuenta: $e');
    }
  }

  static bool isPotentialDuplicate(Map<String, dynamic> n1, Map<String, dynamic> n2) {
    if (n1['id'] == n2['id']) return false;
    final name1 = normalizeText('${n1['nombreCompleto'] ?? '${n1['nombre'] ?? ''} ${n1['apellido1'] ?? ''} ${n1['apellido2'] ?? ''}'}');
    final name2 = normalizeText('${n2['nombreCompleto'] ?? '${n2['nombre'] ?? ''} ${n2['apellido1'] ?? ''} ${n2['apellido2'] ?? ''}'}');
    if (name1.isNotEmpty && name1 == name2) return true;

    final house1 = normalizeText('${n1['numeroCasa'] ?? n1['casa'] ?? ''}');
    final house2 = normalizeText('${n2['numeroCasa'] ?? n2['casa'] ?? ''}');
    if (house1.isNotEmpty && house1 == house2) {
      final addr1 = normalizeText('${n1['direccion'] ?? n1['calle'] ?? ''}');
      final addr2 = normalizeText('${n2['direccion'] ?? n2['calle'] ?? ''}');
      final words1 = addr1.split(' ').where((w) => w.length > 2).toSet();
      final words2 = addr2.split(' ').where((w) => w.length > 2).toSet();
      final shareWords = words1.intersection(words2).isNotEmpty || addr1.contains(addr2) || addr2.contains(addr1);
      if (shareWords) {
        final f1 = normalizeText('${n1['nombre'] ?? ''}');
        final f2 = normalizeText('${n2['nombre'] ?? ''}');
        if (f1.isNotEmpty && f1 == f2) return true;
      }
    }
    return false;
  }

  Future<void> registerNeighbor({
    required String firstName,
    required String lastName1,
    required String lastName2,
    String region = 'Región del Biobío',
    String comuna = 'Coronel',
    String sector = 'Villa Escuadrón Galilea',
    required String address,
    required String houseNumber,
    String phone = '',
    String pin = '',
  }) async {
    final full = '$firstName $lastName1 $lastName2'.trim();
    final fullAddr = '$address #$houseNumber'.trim();
    final displayName = '$full ($fullAddr)';

    this.firstName = firstName.trim();
    this.lastName1 = lastName1.trim();
    this.lastName2 = lastName2.trim();
    this.region = region.trim();
    this.comuna = comuna.trim();
    this.sector = sector.trim();
    this.address = address.trim();
    this.houseNumber = houseNumber.trim();
    this.phone = phone.trim();
    this.pin = pin.trim();
    fullName = full;
    fullAddress = fullAddr;
    neighborName = displayName;
    isRegistered = true;
    isAdmin = false;

    final key = _db.ref('vecinos').push().key!;
    neighborId = key;

    try {
      await _db.ref('vecinos/$key').set({
        'id': key,
        'nombre': this.firstName,
        'apellido1': this.lastName1,
        'apellido2': this.lastName2,
        'nombreCompleto': full,
        'region': this.region,
        'comuna': this.comuna,
        'sector': this.sector,
        'direccion': this.address,
        'calle': this.address,
        'numeroCasa': this.houseNumber,
        'casa': this.houseNumber,
        'direccionCompleta': fullAddr,
        'telefono': this.phone,
        'pin': this.pin,
        'rol': 'vecino',
        'activo': true,
        'tipoPlan': 'prueba',
        'finPrueba': DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
        'createdAt': ServerValue.timestamp,
      }).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Error guardando en Firebase: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_registered', true);
    await prefs.setBool('is_admin', false);
    await prefs.setString('neighbor_id', key);
    await prefs.setString('first_name', this.firstName);
    await prefs.setString('last_name1', this.lastName1);
    await prefs.setString('last_name2', this.lastName2);
    await prefs.setString('region', this.region);
    await prefs.setString('comuna', this.comuna);
    await prefs.setString('sector', this.sector);
    await prefs.setString('address', this.address);
    await prefs.setString('house_number', this.houseNumber);
    await prefs.setString('phone', this.phone);
    await prefs.setString('pin', this.pin);
    await prefs.setString('full_name', full);
    await prefs.setString('full_address', fullAddr);
    await prefs.setString('neighbor_name', displayName);
  }

  Future<int> getEditProfileAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    if (neighborId != null && neighborId!.isNotEmpty) {
      try {
        final snap = await _db.ref('vecinos/$neighborId/intentosEdicion').get().timeout(const Duration(seconds: 4));
        if (snap.exists && snap.value is num) {
          final serverAttempts = (snap.value as num).toInt();
          await prefs.setInt('edit_profile_attempts', serverAttempts);
          return serverAttempts;
        }
      } catch (_) {}
    }
    return prefs.getInt('edit_profile_attempts') ?? 0;
  }

  Future<(bool, String)> updateNeighborProfile({
    required String firstName,
    required String lastName1,
    required String lastName2,
    required String address,
    required String houseNumber,
  }) async {
    final currentAttempts = await getEditProfileAttempts();
    if (currentAttempts >= 3) {
      return (
        false,
        'Has alcanzado el límite de 3 correcciones de datos permitidas. Solicita al Administrador que habilite más intentos o que modifique tus datos en el sistema.'
      );
    }

    final numRegExp = RegExp(r'[0-9]');
    if (numRegExp.hasMatch(firstName) || numRegExp.hasMatch(lastName1) || numRegExp.hasMatch(lastName2)) {
      return (false, 'Los nombres y apellidos no pueden contener números.');
    }

    if (!numRegExp.hasMatch(houseNumber)) {
      return (false, 'El número de casa debe contener al menos un dígito numérico.');
    }

    final (isDup, dupMsg) = await checkDuplicateNeighbor(
      firstName: firstName,
      lastName1: lastName1,
      lastName2: lastName2,
      address: address,
      houseNumber: houseNumber,
      excludeId: neighborId,
    );
    if (isDup) {
      return (false, dupMsg ?? 'Estos datos coinciden con otro vecino ya registrado en la villa.');
    }

    final newAttempts = currentAttempts + 1;
    final full = '$firstName $lastName1 $lastName2'.trim();
    final fullAddr = '$address #$houseNumber'.trim();
    final displayName = isAdmin ? 'ADMIN: $full ($fullAddr)' : '$full ($fullAddr)';

    this.firstName = firstName.trim();
    this.lastName1 = lastName1.trim();
    this.lastName2 = lastName2.trim();
    this.address = address.trim();
    this.houseNumber = houseNumber.trim();
    fullName = full;
    fullAddress = fullAddr;
    neighborName = displayName;

    final updateData = {
      'nombre': this.firstName,
      'apellido1': this.lastName1,
      'apellido2': this.lastName2,
      'nombreCompleto': full,
      'direccion': this.address,
      'numeroCasa': this.houseNumber,
      'direccionCompleta': fullAddr,
      'intentosEdicion': newAttempts,
      'updatedAt': ServerValue.timestamp,
    };

    if (neighborId != null && neighborId!.isNotEmpty) {
      try {
        await _db.ref('vecinos/$neighborId').update(updateData).timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('Error actualizando vecino en Firebase: $e');
      }
    }

    if (isAdmin) {
      try {
        await _db.ref('config/admin').update(updateData).timeout(const Duration(seconds: 8));
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('first_name', this.firstName);
    await prefs.setString('last_name1', this.lastName1);
    await prefs.setString('last_name2', this.lastName2);
    await prefs.setString('address', this.address);
    await prefs.setString('house_number', this.houseNumber);
    await prefs.setString('full_name', full);
    await prefs.setString('full_address', fullAddr);
    await prefs.setString('neighbor_name', displayName);
    await prefs.setInt('edit_profile_attempts', newAttempts);

    return (true, 'Datos actualizados con éxito (Intento $newAttempts de 3).');
  }

  Future<void> adminUpdateNeighbor(
    String targetId, {
    required String firstName,
    required String lastName1,
    required String lastName2,
    required String address,
    required String houseNumber,
  }) async {
    final full = '$firstName $lastName1 $lastName2'.trim();
    final fullAddr = '$address #$houseNumber'.trim();

    final updateData = {
      'nombre': firstName.trim(),
      'apellido1': lastName1.trim(),
      'apellido2': lastName2.trim(),
      'nombreCompleto': full,
      'direccion': address.trim(),
      'numeroCasa': houseNumber.trim(),
      'direccionCompleta': fullAddr,
      'updatedAt': ServerValue.timestamp,
    };

    try {
      await _db.ref('vecinos/$targetId').update(updateData).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Error actualizando vecino desde admin: $e');
    }

    if (targetId == neighborId) {
      this.firstName = firstName.trim();
      this.lastName1 = lastName1.trim();
      this.lastName2 = lastName2.trim();
      this.address = address.trim();
      this.houseNumber = houseNumber.trim();
      fullName = full;
      fullAddress = fullAddr;
      neighborName = isAdmin ? 'ADMIN: $full ($fullAddr)' : '$full ($fullAddr)';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('first_name', this.firstName);
      await prefs.setString('last_name1', this.lastName1);
      await prefs.setString('last_name2', this.lastName2);
      await prefs.setString('address', this.address);
      await prefs.setString('house_number', this.houseNumber);
      await prefs.setString('full_name', full);
      await prefs.setString('full_address', fullAddr);
      await prefs.setString('neighbor_name', neighborName);
    }
  }

  Future<void> adminResetNeighborAttempts(String targetId) async {
    try {
      await _db.ref('vecinos/$targetId/intentosEdicion').set(0).timeout(const Duration(seconds: 6));
      if (targetId == neighborId) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('edit_profile_attempts', 0);
      }
    } catch (e) {
      debugPrint('Error reseteando intentos de vecino: $e');
    }
  }

  Future<void> updateEmergencyAlertDescription(String newDescription) async {
    final clean = newDescription.trim();
    if (clean.isEmpty) return;

    if (currentAlert != null) {
      currentAlert = currentAlert!.copyWith(notes: clean);
      _alerts.add(currentAlert);
    }

    try {
      await _db.ref('emergenciaActual/descripcion').set(clean).timeout(const Duration(seconds: 6));
      final repSnap = await _db.ref('reportes').limitToLast(1).get().timeout(const Duration(seconds: 6));
      if (repSnap.exists && repSnap.value is Map) {
        final key = (repSnap.value as Map).keys.first.toString();
        await _db.ref('reportes/$key/descripcion').set(clean);
      }
    } catch (e) {
      debugPrint('Error actualizando descripción de alerta: $e');
    }
  }

  Future<void> syncReportPhotoToFirebase(String reportId, String base64Image) async {
    try {
      await _db.ref('reportes/$reportId/fotosBytes').push().set(base64Image).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Error subiendo foto a Firebase: $e');
    }
  }

  Future<bool> hasAdminInFirebase() async {
    try {
      final snapshot = await _db.ref('config/admin').get().timeout(const Duration(seconds: 6));
      return snapshot.exists && snapshot.value != null;
    } catch (e) {
      debugPrint('Error comprobando admin en Firebase: $e');
      return false;
    }
  }

  Future<bool> verifyAdminPin(String pin) async {
    try {
      final snapshot = await _db.ref('config/admin/pin').get().timeout(const Duration(seconds: 6));
      if (!snapshot.exists || snapshot.value == null) {
        return pin.trim() == '7866' || pin.trim() == '1234';
      }
      return snapshot.value.toString().trim() == pin.trim();
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      final localPin = prefs.getString('admin_pin') ?? '7866';
      return pin.trim() == localPin.trim() || pin.trim() == '7866';
    }
  }

  Future<void> registerAdmin({
    required String firstName,
    required String lastName1,
    required String lastName2,
    String region = 'Región del Biobío',
    String comuna = 'Coronel',
    String sector = 'Villa Escuadrón Galilea',
    required String address,
    required String houseNumber,
    String phone = '',
    required String pin,
  }) async {
    final full = '$firstName $lastName1 $lastName2'.trim();
    final fullAddr = '$address #$houseNumber'.trim();
    final displayName = 'ADMIN: $full ($fullAddr)';

    this.firstName = firstName.trim();
    this.lastName1 = lastName1.trim();
    this.lastName2 = lastName2.trim();
    this.region = region.trim();
    this.comuna = comuna.trim();
    this.sector = sector.trim();
    this.address = address.trim();
    this.houseNumber = houseNumber.trim();
    this.phone = phone.trim();
    this.pin = pin.trim();
    fullName = full;
    fullAddress = fullAddr;
    neighborName = displayName;
    isRegistered = true;
    isAdmin = true;

    final key = _db.ref('vecinos').push().key!;
    neighborId = key;

    final adminData = {
      'id': key,
      'nombre': this.firstName,
      'apellido1': this.lastName1,
      'apellido2': this.lastName2,
      'nombreCompleto': full,
      'region': this.region,
      'comuna': this.comuna,
      'sector': this.sector,
      'direccion': this.address,
      'calle': this.address,
      'numeroCasa': this.houseNumber,
      'casa': this.houseNumber,
      'direccionCompleta': fullAddr,
      'telefono': this.phone,
      'pin': pin.trim(),
      'rol': 'administrador',
      'activo': true,
      'createdAt': ServerValue.timestamp,
    };

    try {
      await _db.ref('config/admin').set(adminData).timeout(const Duration(seconds: 8));
      await _db.ref('vecinos/$key').set(adminData).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Error guardando admin en Firebase: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_registered', true);
    await prefs.setBool('is_admin', true);
    await prefs.setString('admin_pin', pin.trim());
    await prefs.setString('neighbor_id', key);
    await prefs.setString('first_name', this.firstName);
    await prefs.setString('last_name1', this.lastName1);
    await prefs.setString('last_name2', this.lastName2);
    await prefs.setString('region', this.region);
    await prefs.setString('comuna', this.comuna);
    await prefs.setString('sector', this.sector);
    await prefs.setString('address', this.address);
    await prefs.setString('house_number', this.houseNumber);
    await prefs.setString('phone', this.phone);
    await prefs.setString('pin', this.pin);
    await prefs.setString('full_name', full);
    await prefs.setString('full_address', fullAddr);
    await prefs.setString('neighbor_name', displayName);
  }

  Future<bool> loginAsAdmin(String pin, {bool biometricOverride = false}) async {
    final ok = biometricOverride || await verifyAdminPin(pin);
    if (ok) {
      isAdmin = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_admin', true);
      // Intentar cargar datos del admin desde Firebase si existen
      try {
        final snap = await _db.ref('config/admin').get().timeout(const Duration(seconds: 6));
        if (snap.exists && snap.value is Map) {
          final m = Map<String, dynamic>.from(snap.value as Map);
          firstName = m['nombre'] ?? firstName;
          lastName1 = m['apellido1'] ?? lastName1;
          lastName2 = m['apellido2'] ?? lastName2;
          address = m['direccion'] ?? address;
          houseNumber = m['numeroCasa'] ?? houseNumber;
          fullName = m['nombreCompleto'] ?? '$firstName $lastName1 $lastName2'.trim();
          fullAddress = m['direccionCompleta'] ?? '$address #$houseNumber'.trim();
          neighborName = 'ADMIN: $fullName ($fullAddress)';
          isRegistered = true;
          await prefs.setBool('is_registered', true);
          await prefs.setString('neighbor_name', neighborName);
          await prefs.setString('full_name', fullName);
          await prefs.setString('full_address', fullAddress);
        }
      } catch (_) {}
    }
    return ok;
  }

  Future<void> logoutAdmin() async {
    isAdmin = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_admin', false);
    if (fullName.isNotEmpty && fullAddress.isNotEmpty) {
      neighborName = '$fullName ($fullAddress)';
      await prefs.setString('neighbor_name', neighborName);
    }
  }

  Future<void> sendEmergencyAlert({
    required String type,
    String description = '',
    String location = '',
    double? latitude,
    double? longitude,
    int photoCount = 0,
    String color = '#DC2626',
    String icon = '🚨',
    String customLocation = '',
  }) async {
    final now = DateTime.now();
    final ymd = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final randSuffix = (now.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0');
    final reportCode = '#REP-$ymd-$randSuffix';

    // 1. Activar inmediatamente en local para que el usuario no dependa de la red
    final localAlert = AlertModel(
      id: 'local_${now.millisecondsSinceEpoch}',
      type: type,
      sender: neighborName,
      notes: description,
      location: location,
      latitude: latitude,
      longitude: longitude,
      timestamp: now,
      active: true,
      photoCount: photoCount,
      color: color,
      icon: icon,
      customLocation: customLocation,
      reportCode: reportCode,
    );
    currentAlert = localAlert;
    _alerts.add(localAlert);
    final localKey = getAlertKey(localAlert);
    _lastSoundedAlertId = localKey;
    _persistLastSoundedAlert(localKey);
    await AlarmPlayerService().startAlarm(type);

    if (Platform.isAndroid) {
      FlutterForegroundTask.updateService(
        notificationTitle: '🚨 ¡ALERTA VECINAL: $type!',
        notificationText: 'Vecino: $neighborName $description'.trim(),
      );
      FlutterForegroundTask.launchApp();
    }

    // 2. Enviar a Firebase Realtime Database
    final data = {
      'tipo': type,
      'emisor': neighborName,
      'descripcion': description,
      'ubicacion': location,
      'latitude': latitude,
      'longitude': longitude,
      'fotosTomadas': photoCount,
      'color': color,
      'icono': icon,
      'ubicacionIncidente': customLocation,
      'codigoReporte': reportCode,
      'timestamp': ServerValue.timestamp,
    };

    bool sentViaSdk = false;
    try {
      await _db.ref('emergenciaActual').set(data).timeout(const Duration(seconds: 4));
      await _db.ref('reportes').push().set(data).timeout(const Duration(seconds: 4));
      sentViaSdk = true;
    } catch (e) {
      debugPrint('Timeout o fallo de WebSocket al emitir alerta: $e. Usando HTTPS REST Fallback...');
    }

    if (!sentViaSdk) {
      try {
        final restData = Map<String, dynamic>.from(data);
        restData['timestamp'] = now.millisecondsSinceEpoch;
        final urlEmergencia = Uri.parse('https://alerta-vecinal-coronel-default-rtdb.firebaseio.com/emergenciaActual.json');
        final urlReportes = Uri.parse('https://alerta-vecinal-coronel-default-rtdb.firebaseio.com/reportes.json');
        final bodyStr = jsonEncode(restData);
        await Future.wait([
          http.put(urlEmergencia, body: bodyStr).timeout(const Duration(seconds: 4)),
          http.post(urlReportes, body: bodyStr).timeout(const Duration(seconds: 4)),
        ]);
        debugPrint('Alerta emitida exitosamente mediante HTTPS REST Fallback');
      } catch (restErr) {
        debugPrint('Error en REST Fallback: $restErr');
      }
    }
  }

  Future<void> cancelEmergencyAlert() async {
    currentAlert = null;
    _alerts.add(null);
    await AlarmPlayerService().stopAlarm();

    if (Platform.isAndroid) {
      FlutterForegroundTask.updateService(
        notificationTitle: '🚨 Vigilancia Vecinal Activa',
        notificationText: 'Sistema conectado y red comunitaria protegida.',
      );
    }

    bool removedViaSdk = false;
    try {
      await _db.ref('emergenciaActual').remove().timeout(const Duration(seconds: 4));
      removedViaSdk = true;
    } catch (e) {
      debugPrint('Error al remover emergenciaActual vía SDK: $e');
    }

    if (!removedViaSdk) {
      try {
        final url = Uri.parse('https://alerta-vecinal-coronel-default-rtdb.firebaseio.com/emergenciaActual.json');
        await http.delete(url).timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
  }

  Future<List<Map<String, dynamic>>> reports() async {
    try {
      final event = await _db.ref('reportes').get().timeout(const Duration(seconds: 8));
      final value = event.value;
      if (value is! Map) return [];
      final list = value.entries.map((e) => {'id': e.key, ...(Map<String, dynamic>.from(e.value as Map))}).toList();
      list.sort((a, b) => (b['timestamp'] ?? 0).toString().compareTo((a['timestamp'] ?? 0).toString()));
      return list;
    } catch (e) {
      debugPrint('Error al obtener reportes: $e');
      return [];
    }
  }

  Future<void> deleteReport(String id) async {
    try {
      await _db.ref('reportes/$id').remove().timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('Error al eliminar reporte: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getNeighbors() async {
    try {
      final event = await _db.ref('vecinos').get().timeout(const Duration(seconds: 8));
      final value = event.value;
      if (value is! Map) return [];
      return value.entries.map((e) => {'id': e.key, ...(Map<String, dynamic>.from(e.value as Map))}).toList();
    } catch (e) {
      debugPrint('Error al obtener vecinos: $e');
      return [];
    }
  }

  Future<void> toggleNeighborStatus(String id, bool active) async {
    try {
      await _db.ref('vecinos/$id/activo').set(active).timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('Error al cambiar estado del vecino: $e');
    }
  }

  Map<String, dynamic> getTrialStatus(Map<dynamic, dynamic> neighborData) {
    final role = neighborData['rol'] ?? 'vecino';
    if (role == 'administrador') {
      return {
        'isTrial': false,
        'isPermanent': true,
        'isExpired': false,
        'label': 'Administrador',
        'daysLeft': 9999,
        'hoursLeft': 0,
        'minutesLeft': 0,
        'secondsLeft': 0,
        'statusText': 'Plan Vitalicio Administrador',
      };
    }

    final tipoPlan = neighborData['tipoPlan'] ?? 'prueba';
    if (tipoPlan == 'definitivo' || tipoPlan == 'normal') {
      return {
        'isTrial': false,
        'isPermanent': true,
        'isExpired': false,
        'label': 'Plan Definitivo Adquirido',
        'daysLeft': 9999,
        'hoursLeft': 0,
        'minutesLeft': 0,
        'secondsLeft': 0,
        'statusText': 'Cuenta Definitiva Activa',
      };
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final createdAt = (neighborData['createdAt'] is num)
        ? (neighborData['createdAt'] as num).toInt()
        : now;
    final finPrueba = (neighborData['finPrueba'] is num)
        ? (neighborData['finPrueba'] as num).toInt()
        : createdAt + (30 * 24 * 60 * 60 * 1000);

    final diffMs = finPrueba - now;
    if (diffMs <= 0) {
      return {
        'isTrial': true,
        'isPermanent': false,
        'isExpired': true,
        'label': 'Prueba Vencida',
        'daysLeft': 0,
        'hoursLeft': 0,
        'minutesLeft': 0,
        'secondsLeft': 0,
        'statusText': 'Mes de prueba finalizado',
      };
    }

    final diff = Duration(milliseconds: diffMs);
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;
    final seconds = diff.inSeconds % 60;

    return {
      'isTrial': true,
      'isPermanent': false,
      'isExpired': false,
      'label': '$days días de prueba',
      'daysLeft': days,
      'hoursLeft': hours,
      'minutesLeft': minutes,
      'secondsLeft': seconds,
      'statusText': '$days d, $hours h, $minutes m restantes',
    };
  }

  Future<void> setNeighborPlan(String neighborId, String planType) async {
    try {
      await _db.ref('vecinos/$neighborId/tipoPlan').set(planType).timeout(const Duration(seconds: 6));
      if (planType == 'definitivo') {
        await _db.ref('vecinos/$neighborId/activo').set(true);
      }
    } catch (e) {
      debugPrint('Error actualizando plan del vecino: $e');
    }
  }

  Future<void> extendNeighborTrial(String neighborId, {int days = 30}) async {
    final newEnd = DateTime.now().add(Duration(days: days)).millisecondsSinceEpoch;
    try {
      await _db.ref('vecinos/$neighborId/tipoPlan').set('prueba');
      await _db.ref('vecinos/$neighborId/finPrueba').set(newEnd);
      await _db.ref('vecinos/$neighborId/activo').set(true);
    } catch (e) {
      debugPrint('Error extendiendo prueba: $e');
    }
  }

  Future<void> expireNeighborTrial(String neighborId) async {
    final pastEnd = DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
    try {
      await _db.ref('vecinos/$neighborId/tipoPlan').set('prueba');
      await _db.ref('vecinos/$neighborId/finPrueba').set(pastEnd);
    } catch (e) {
      debugPrint('Error venciendo prueba: $e');
    }
  }

  Future<(bool, String)> getNeighborActiveStatus() async {
    if (neighborId == null || neighborId!.isEmpty) return (true, '');
    try {
      final snap = await _db.ref('vecinos/$neighborId').get().timeout(const Duration(seconds: 6));
      if (!snap.exists || snap.value is! Map) return (true, '');
      final data = Map<dynamic, dynamic>.from(snap.value as Map);
      if (data['activo'] == false) {
        return (false, 'Tu cuenta ha sido desactivada por la administración comunitaria.');
      }
      final trial = getTrialStatus(data);
      if (trial['isExpired'] == true) {
        return (
          false,
          'Tu período de prueba gratuito de 1 mes ha finalizado.\n\nPara seguir protegido y hacer sonar la alarma, solicita al Administrador que active tu Plan Definitivo.'
        );
      }
      return (true, '');
    } catch (_) {
      return (true, '');
    }
  }

  Future<bool> isNeighborActive() async {
    final (active, _) = await getNeighborActiveStatus();
    return active;
  }

  Future<void> deleteNeighbor(String id) async {
    try {
      await _db.ref('vecinos/$id').remove().timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('Error al borrar vecino: $e');
    }
  }

  Future<void> addCustomButton({
    required String title,
    required String subtitle,
    required String icon,
    required String color,
    required bool requiresDescription,
    required bool allowsPhotos,
  }) async {
    final key = _db.ref('botones').push().key!;
    await _db.ref('botones/$key').set({
      'id': key,
      'titulo': title.trim(),
      'subtitulo': subtitle.trim(),
      'icono': icon.trim(),
      'color': color.trim(),
      'requiereDesc': requiresDescription,
      'permiteFotos': allowsPhotos,
      'createdAt': ServerValue.timestamp,
    }).timeout(const Duration(seconds: 8));
  }

  Future<void> deleteCustomButton(String id) async {
    try {
      await _db.ref('botones/$id').remove().timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('Error al borrar botón: $e');
    }
  }

  Future<void> restoreDefaultButtons() async {
    final Map<String, dynamic> data = {};
    for (int i = 0; i < defaults.length; i++) {
      final b = defaults[i];
      data['${i + 1}'] = {
        'id': '${i + 1}',
        'titulo': b.title,
        'subtitulo': b.subtitle,
        'icono': b.icon,
        'requiereDesc': b.requiresDescription,
        'permiteFotos': b.allowsPhotos,
        'color': b.color,
      };
    }
    await _db.ref('botones').set(data).timeout(const Duration(seconds: 8));
  }

  Future<String> testFirebaseConnection() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        final cred = await FirebaseAuth.instance.signInAnonymously();
        user = cred.user;
      }
      final testRef = _db.ref('_diagnostico');
      await testRef.set({
        'test': true,
        'uid': user?.uid,
        'timestamp': ServerValue.timestamp,
      }).timeout(const Duration(seconds: 6));
      await testRef.remove().timeout(const Duration(seconds: 6));
      return 'OK: Conexión y permisos de lectura/escritura correctos en Firebase. (UID: ${user?.uid})';
    } catch (e) {
      return 'ERROR: $e\n\nVerifica en la Consola de Firebase que la Autenticación Anónima esté activada y que las reglas de Realtime Database permitan lectura/escritura.';
    }
  }

  Future<String> getAdminWhatsApp() async {
    try {
      final snap = await _db.ref('config/admin_whatsapp').get().timeout(const Duration(seconds: 5));
      if (snap.exists && snap.value != null && snap.value.toString().trim().isNotEmpty) {
        return snap.value.toString().trim();
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('admin_whatsapp') ?? '+56912345678';
  }

  Future<void> setAdminWhatsApp(String phone) async {
    final clean = phone.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('admin_whatsapp', clean);
    try {
      await _db.ref('config/admin_whatsapp').set(clean).timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('Error guardando WhatsApp admin en Firebase: $e');
    }
  }

  static const int currentVersionCode = 104; // v1.0.4
  static const String currentVersionName = '1.0.4';

  int _dismissedUpdateVersion = 0;
  int get dismissedUpdateVersion => _dismissedUpdateVersion;

  Future<void> dismissUpdate(int versionCode) async {
    _dismissedUpdateVersion = versionCode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('dismissed_update_version', versionCode);
    } catch (_) {}
  }

  bool isUpdateDismissed(int versionCode) {
    return _dismissedUpdateVersion >= versionCode;
  }

  Stream<Map<String, dynamic>?> get appUpdateStream {
    return _db.ref('config/app_update').onValue.map((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        final m = Map<String, dynamic>.from(val);
        final remoteCode = (m['versionCode'] is num) ? (m['versionCode'] as num).toInt() : 0;
        // Solo mostrar si es una versión estrictamente SUPERIOR a la actual instalada
        // Y el usuario no ha descartado o actualizado ya a esta versión
        if (remoteCode > currentVersionCode && remoteCode > _dismissedUpdateVersion) {
          return m;
        }
      }
      return null;
    });
  }

  static String convertDriveToDirectDownload(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return trimmed;

    // Detectar enlaces de Google Drive y convertirlos a descarga directa de APK
    if (trimmed.contains('drive.google.com') ||
        trimmed.contains('drive.usercontent.google.com') ||
        trimmed.contains('docs.google.com')) {
      final regExp = RegExp(r'(?:/file/d/|/d/|[?&]id=)([a-zA-Z0-9_-]{15,})');
      final match = regExp.firstMatch(trimmed);
      if (match != null && match.groupCount >= 1) {
        final fileId = match.group(1)!;
        return 'https://drive.usercontent.google.com/download?id=$fileId&export=download&confirm=t';
      }
    }
    return trimmed;
  }

  Future<void> publishAppUpdate({
    required int versionCode,
    required String versionName,
    required String downloadUrl,
    required String notes,
  }) async {
    final cleanUrl = convertDriveToDirectDownload(downloadUrl);
    final data = {
      'versionCode': versionCode,
      'versionName': versionName.trim(),
      'downloadUrl': cleanUrl,
      'notes': notes.trim(),
      'timestamp': ServerValue.timestamp,
    };
    await setApkDownloadUrl(cleanUrl);
    try {
      await _db.ref('config/app_update').set(data).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Error publicando actualización en Firebase: $e');
    }
  }

  Future<Map<String, dynamic>?> getLatestAppUpdateInfo() async {
    try {
      final snap = await _db.ref('config/app_update').get().timeout(const Duration(seconds: 5));
      if (snap.exists && snap.value is Map) {
        return Map<String, dynamic>.from(snap.value as Map);
      }
    } catch (_) {}
    return null;
  }

  Future<String> getApkDownloadUrl() async {
    try {
      final snap = await _db.ref('config/apk_download_url').get().timeout(const Duration(seconds: 5));
      if (snap.exists && snap.value != null && snap.value.toString().trim().isNotEmpty) {
        return convertDriveToDirectDownload(snap.value.toString().trim());
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('apk_download_url') ?? 'https://github.com/alerta-vecinal/releases';
    return convertDriveToDirectDownload(stored);
  }

  Future<void> setApkDownloadUrl(String url) async {
    final clean = convertDriveToDirectDownload(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('apk_download_url', clean);
    try {
      await _db.ref('config/apk_download_url').set(clean).timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('Error guardando URL de APK en Firebase: $e');
    }
  }

  Future<int> clearOldReports({int days = 30}) async {
    int count = 0;
    try {
      final snap = await _db.ref('reportes').get().timeout(const Duration(seconds: 8));
      if (!snap.exists || snap.value is! Map) return 0;
      final map = Map<dynamic, dynamic>.from(snap.value as Map);
      final threshold = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;

      for (final entry in map.entries) {
        final val = entry.value;
        if (val is Map && val['timestamp'] is num) {
          if ((val['timestamp'] as num) < threshold) {
            await _db.ref('reportes/${entry.key}').remove();
            count++;
          }
        }
      }
    } catch (e) {
      debugPrint('Error limpiando reportes antiguos: $e');
    }
    return count;
  }

  Future<int> clearTestReports() async {
    int count = 0;
    try {
      final snap = await _db.ref('reportes').get().timeout(const Duration(seconds: 8));
      if (!snap.exists || snap.value is! Map) return 0;
      final map = Map<dynamic, dynamic>.from(snap.value as Map);

      for (final entry in map.entries) {
        final val = entry.value;
        if (val is Map && (val['tipo'] == 'PRUEBA DE SISTEMA' || '${val['descripcion']}'.contains('Prueba'))) {
          await _db.ref('reportes/${entry.key}').remove();
          count++;
        }
      }
    } catch (e) {
      debugPrint('Error limpiando reportes de prueba: $e');
    }
    return count;
  }

  Future<Map<String, dynamic>> exportAllDataJson() async {
    final Map<String, dynamic> data = {
      'fecha_exportacion': DateTime.now().toIso8601String(),
      'sistema': 'Centinela Urbano - Alerta Vecinal',
    };
    try {
      final vecSnap = await _db.ref('vecinos').get();
      if (vecSnap.exists) data['vecinos'] = vecSnap.value;
      final repSnap = await _db.ref('reportes').get();
      if (repSnap.exists) data['reportes'] = repSnap.value;
      final botSnap = await _db.ref('botones').get();
      if (botSnap.exists) data['botones'] = botSnap.value;
      final cfgSnap = await _db.ref('config').get();
      if (cfgSnap.exists) data['config'] = cfgSnap.value;
    } catch (e) {
      data['error'] = e.toString();
    }
    return data;
  }

  Future<String> getSeguridadCiudadanaPhone() async {
    try {
      final snap = await _db.ref('config/telefono_seguridad').get().timeout(const Duration(seconds: 5));
      if (snap.exists && snap.value != null && snap.value.toString().trim().isNotEmpty) {
        return snap.value.toString().trim();
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('telefono_seguridad') ?? '1414';
  }

  Future<void> setSeguridadCiudadanaPhone(String phone) async {
    final clean = phone.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('telefono_seguridad', clean);
    try {
      await _db.ref('config/telefono_seguridad').set(clean).timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('Error guardando teléfono seguridad en Firebase: $e');
    }
  }

  Stream<Map<String, dynamic>?> get communityNoticeStream {
    return _db.ref('comunicados/actual').onValue.map((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        return Map<String, dynamic>.from(val);
      }
      return null;
    });
  }

  Future<Map<String, dynamic>?> getLatestCommunityNotice() async {
    try {
      final snap = await _db.ref('comunicados/actual').get().timeout(const Duration(seconds: 5));
      if (snap.exists && snap.value is Map) {
        return Map<String, dynamic>.from(snap.value as Map);
      }
    } catch (_) {}
    return null;
  }

  Future<void> publishCommunityNotice({
    required String title,
    required String message,
  }) async {
    final now = DateTime.now();
    final data = {
      'titulo': title.trim(),
      'mensaje': message.trim(),
      'autor': fullName.isNotEmpty ? fullName : neighborName,
      'timestamp': ServerValue.timestamp,
      'fecha': '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}',
    };
    try {
      await _db.ref('comunicados/actual').set(data).timeout(const Duration(seconds: 8));
      await _db.ref('comunicados/historial').push().set(data).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Error publicando comunicado en Firebase: $e');
    }
  }

  Future<void> deleteCommunityNotice() async {
    try {
      await _db.ref('comunicados/actual').remove().timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('Error eliminando comunicado en Firebase: $e');
    }
  }

  Future<void> updateConfig({required String newUrl, required String newName}) async {
    neighborName = newName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('neighbor_name', neighborName);
  }

  Future<List<String>> getReportPhotos(String reportId, {String? reportCode}) async {
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getStringList('report_photos_$reportId') ?? [];
    if (local.isEmpty && reportCode != null && reportCode.isNotEmpty) {
      return syncReportPhotosFromCloud(reportId, reportCode);
    }
    return local;
  }

  Future<void> addReportPhoto(String reportId, String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('report_photos_$reportId') ?? [];
    if (!list.contains(filePath)) {
      list.add(filePath);
      await prefs.setStringList('report_photos_$reportId', list);
    }
  }

  Future<void> removeReportPhoto(String reportId, String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('report_photos_$reportId') ?? [];
    list.remove(filePath);
    await prefs.setStringList('report_photos_$reportId', list);
  }

  Future<void> uploadReportPhotosCloud(String reportCode, List<String> localFilePaths) async {
    if (localFilePaths.isEmpty) return;
    try {
      final cleanKey = reportCode.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
      if (cleanKey.isEmpty) return;

      final List<String> base64Images = [];
      for (final p in localFilePaths) {
        try {
          final file = File(p);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            base64Images.add(base64Encode(bytes));
          }
        } catch (_) {}
      }

      if (base64Images.isNotEmpty) {
        await _db.ref('evidenciasReportes/$cleanKey/fotos').set(base64Images).timeout(const Duration(seconds: 12));
      }
    } catch (e) {
      debugPrint('Error subiendo fotos a la nube: $e');
    }
  }

  Future<List<String>> syncReportPhotosFromCloud(String reportId, String reportCode) async {
    final local = await getReportPhotos(reportId);
    try {
      final cleanKey = reportCode.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
      if (cleanKey.isEmpty) return local;

      final snap = await _db.ref('evidenciasReportes/$cleanKey/fotos').get().timeout(const Duration(seconds: 6));
      if (snap.exists && snap.value is List) {
        final list = List<dynamic>.from(snap.value as List);
        final dir = await getApplicationDocumentsDirectory();
        final photosDir = Directory('${dir.path}/evidence_photos');
        if (!await photosDir.exists()) {
          await photosDir.create(recursive: true);
        }

        for (int i = 0; i < list.length; i++) {
          final b64 = list[i];
          if (b64 is String && b64.isNotEmpty) {
            final fileName = 'evidence_${cleanKey}_$i.jpg';
            final file = File('${photosDir.path}/$fileName');
            if (!await file.exists()) {
              final bytes = base64Decode(b64);
              await file.writeAsBytes(bytes);
            }
            await addReportPhoto(reportId, file.path);
          }
        }
      }
    } catch (e) {
      debugPrint('Error sincronizando fotos de evidencia desde la nube: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('report_photos_$reportId') ?? [];
  }

  Future<void> reconnect() async {
    try {
      debugPrint('Forzando reconexión a Firebase...');
      _db.goOnline();

      // Asegurar sesión anónima si se cerró
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously().timeout(const Duration(seconds: 4));
      }

      // Sondeo activo inmediato del nodo de emergencia
      final snap = await _db.ref('emergenciaActual').get().timeout(const Duration(seconds: 4));
      if (snap.exists && snap.value is Map) {
        final val = Map<dynamic, dynamic>.from(snap.value as Map);
        if (val['tipo'] != null) {
          _processIncomingAlertData(snap.key ?? 'active', val);
        }
      } else {
        if (currentAlert != null) {
          _processIncomingAlertData('none', null);
        }
      }
      isConnected = true;
      _connection.add(true);
    } catch (e) {
      debugPrint('Reconexión WebSocket falló: $e. Probando fallback REST...');
      try {
        final url = Uri.parse('https://alerta-vecinal-coronel-default-rtdb.firebaseio.com/emergenciaActual.json');
        final res = await http.get(url).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200 && res.body.isNotEmpty && res.body != 'null') {
          final data = jsonDecode(res.body);
          if (data is Map && data['tipo'] != null) {
            _processIncomingAlertData('rest_fallback', Map<dynamic, dynamic>.from(data));
          }
        } else if (res.statusCode == 200 && (res.body == 'null' || res.body.isEmpty)) {
          if (currentAlert != null) {
            _processIncomingAlertData('none', null);
          }
        }
        isConnected = true;
        _connection.add(true);
      } catch (_) {
        // En caso de modo avión o sin red
      }
    }
  }

  void connect() => reconnect();
  void disconnect() {
    _heartbeatTimer?.cancel();
    _db.goOffline();
  }
}
