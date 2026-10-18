import 'dart:io';
import 'package:flutter/services.dart';

class NativeAlertService {
  static const MethodChannel _channel = MethodChannel('com.comunidad.alerta/native_alert');

  /// Verifica si la aplicación tiene permiso de ignorar optimizaciones de batería
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final bool? result = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Solicita el permiso para ignorar optimizaciones de batería al sistema Android
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {
      // Ignorar o registrar error
    }
  }

  /// Enciende la pantalla y muestra la actividad sobre la pantalla de bloqueo
  static Future<void> wakeUpAndUnlock() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('wakeUpAndUnlock');
    } catch (e) {
      // Error silencioso en fallback
    }
  }

  /// Establece el volumen de alarma y multimedia al 100% de su capacidad
  static Future<void> setMaxVolume() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setMaxVolume');
    } catch (e) {
      // Error silencioso en fallback
    }
  }

  /// Muestra una notificación del sistema para comunicados oficiales comunitarios
  static Future<void> showCommunityNotification({
    required String title,
    required String message,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('showCommunityNotification', {
        'title': title,
        'message': message,
      });
    } catch (_) {
      // Fallback silencioso
    }
  }

  /// Envía imágenes y texto directamente al chat de WhatsApp del número especificado (Admin) sin selector
  static Future<bool> shareWhatsAppDirect({
    required String phone,
    required String text,
    List<String> imagePaths = const [],
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? res = await _channel.invokeMethod<bool>('shareWhatsAppDirect', {
        'phone': phone,
        'text': text,
        'imagePaths': imagePaths,
      });
      return res ?? false;
    } catch (e) {
      return false;
    }
  }
}
