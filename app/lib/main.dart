import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'screens/home_screen.dart';
import 'screens/register_screen.dart';
import 'services/alarm_sync_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyC-6N3mPzQYwK9dKX-IBG4HP17lwJW3tWE',
      appId: '1:48694275906:android:6c080786161758009ee2db',
      messagingSenderId: '48694275906',
      projectId: 'alerta-vecinal-coronel',
      databaseURL: 'https://alerta-vecinal-coronel-default-rtdb.firebaseio.com',
      storageBucket: 'alerta-vecinal-coronel.firebasestorage.app',
    ),
  );

  // Habilitar persistencia offline en disco para respuesta inmediata en datos móviles
  try {
    FirebaseDatabase.instance.setPersistenceEnabled(true);
    FirebaseDatabase.instance.setPersistenceCacheSizeBytes(50 * 1024 * 1024); // 50MB
  } catch (e) {
    debugPrint('Firebase Persistence notice: $e');
  }

  // Inicializar tema guardado (claro u oscuro)
  await ThemeService().init();

  // Inicializar puerto de comunicación de primer plano
  FlutterForegroundTask.initCommunicationPort();

  // Inicializar servicios en segundo plano y conexión
  await AlarmSyncService().init();

  runApp(const AlertaVecinalApp());
}

class AlertaVecinalApp extends StatelessWidget {
  const AlertaVecinalApp({super.key});

  @override
  Widget build(BuildContext context) {
    final isRegistered = AlarmSyncService().isRegistered;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService().themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'Alerta Vecinal',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          home: isRegistered ? const HomeScreen() : const RegisterScreen(),
        );
      },
    );
  }
}
