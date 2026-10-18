# Alerta Vecinal Flutter

Migración Flutter de `../alerta-vecinal-2`. La app usa Firebase Realtime
Database y autenticación anónima, sin eliminar ni modificar la aplicación Expo.

## Funciones migradas

- Registro de vecino en `vecinos`.
- Alertas fijas y botones dinámicos (`botones`), con descripción opcional.
- GPS mediante `geolocator` y coordenadas guardadas en `emergenciaActual`/`reportes`.
- Sirena local por tipo (robo, incendio, médico), vibración y pantalla activa.
- Historial de reportes.
- Cámara y fotos locales (no se suben a Firebase).
- Acceso discreto al panel administrativo mediante pulsación larga en el título.
- `google-services.json` y sonidos/imágenes copiados desde la app Expo.

Activa **Authentication → Anonymous** en el proyecto Firebase. El SDK Flutter
no está instalado en el entorno de migración, por lo que `flutter pub get`,
análisis y APK deben validarse en una máquina con Flutter instalado.
