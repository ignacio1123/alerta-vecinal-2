import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'native_alert_service.dart';

class AlarmPlayerService {
  static final AlarmPlayerService _instance = AlarmPlayerService._internal();
  factory AlarmPlayerService() => _instance;
  AlarmPlayerService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  Future<void> init() async {
    try {
      final audioContext = AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransientExclusive,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {
            AVAudioSessionOptions.duckOthers,
            AVAudioSessionOptions.defaultToSpeaker,
          },
        ),
      );
      await AudioPlayer.global.setAudioContext(audioContext);
      await _audioPlayer.setAudioContext(audioContext);
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.setVolume(1.0);
    } catch (_) {}
  }

  /// Inicia el sonido de alerta máxima, vibración y despierta la pantalla
  Future<void> startAlarm([String type = '']) async {
    if (_isPlaying) return;
    _isPlaying = true;

    // 1. Establecer volumen máximo y despertar pantalla del dispositivo
    try {
      await NativeAlertService.setMaxVolume();
      await NativeAlertService.wakeUpAndUnlock();
    } catch (_) {}

    // 2. Levantar la aplicación si la pantalla está bloqueada o en segundo plano
    if (Platform.isAndroid) {
      try {
        FlutterForegroundTask.launchApp();
      } catch (_) {}
    }

    // 3. Mantener pantalla activa
    try {
      await WakelockPlus.enable();
    } catch (_) {}

    // 4. Vibración en patrón penetrante (repitiendo)
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(
          pattern: [0, 600, 200, 600, 200, 1000, 400],
          repeat: 0,
          intensities: [0, 255, 0, 255, 0, 255, 0],
        );
      }
    } catch (_) {}

    // 5. Configurar canal de alarma y reproducir sirena en bucle a todo volumen
    try {
      final audioContext = AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransientExclusive,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {
            AVAudioSessionOptions.duckOthers,
            AVAudioSessionOptions.defaultToSpeaker,
          },
        ),
      );
      await _audioPlayer.setAudioContext(audioContext);
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.setVolume(1.0);

      final upper = type.toUpperCase();
      final sound = upper.contains('INCENDIO')
          ? 'sounds/incendio.wav'
          : (upper.contains('MÉDICO') || upper.contains('MEDICO') || upper.contains('AMBULANCIA'))
              ? 'sounds/ambulancia.wav'
              : (upper.contains('ROBO') || upper.contains('INTRUS'))
                  ? 'sounds/alarma_robo.wav'
                  : 'sounds/alarm_siren.wav';

      await _audioPlayer.play(
        AssetSource(sound),
        mode: PlayerMode.mediaPlayer,
        volume: 1.0,
      );
    } catch (_) {}
  }

  /// Detiene la sirena de alarma y cancela la vibración
  Future<void> stopAlarm() async {
    _isPlaying = false;

    try {
      await _audioPlayer.stop();
    } catch (_) {}

    try {
      Vibration.cancel();
    } catch (_) {}

    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }
}
