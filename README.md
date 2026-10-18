# 🛡️ Centinela Urbano — Sistema de Alerta Vecinal & Seguridad Comunitaria

<div align="center">

![Centinela Urbano Banner](https://img.shields.io/badge/Centinela_Urbano-Seguridad_Comunitaria-0F172A?style=for-the-badge&logo=shield&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Android](https://img.shields.io/badge/Android-8.0%2B-3DDC84?style=for-the-badge&logo=android&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-Realtime_DB-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)
![License](https://img.shields.io/badge/License-WTFPL-brightgreen?style=for-the-badge)

<br/>

### 📲 Descarga Directa de la Aplicación (APK)

[![Descargar APK](https://img.shields.io/badge/DESCARGAR_APK_OFICIAL-v1.0.4_(72.7_MB)-059669?style=for-the-badge&logo=android&logoColor=white)](https://github.com/ignacio1123/alerta-vecinal-2/raw/master/releases/AlertaVecinal-Release.apk)

**[👉 Haz clic aquí para descargar `AlertaVecinal-Release.apk` directamente a tu celular](https://github.com/ignacio1123/alerta-vecinal-2/raw/master/releases/AlertaVecinal-Release.apk)**

*Compatible con cualquier teléfono Android 8.0 o superior. Instalación directa sin tiendas ni intermediarios.*

</div>

---

## 📋 Descripción del Proyecto

**Centinela Urbano** es una plataforma integral de seguridad vecinal diseñada para villas, pasajes, condominios y comités comunitarios. Resuelve la ineficacia de los grupos de mensajería tradicionales (como WhatsApp), garantizando que ante un evento de riesgo, **todos los teléfonos de la comunidad suenen con una sirena penetrante a máximo volumen**, enciendan sus pantallas y muestren la ubicación exacta de la emergencia en tiempo real, incluso si los teléfonos están bloqueados o en silencio.

El sistema fue desarrollado e implementado a medida para la comunidad **Villa Escuadrón Galilea (Coronel, Región del Biobío, Chile)**, ofreciendo control de cupos por hogar, generación de expedientes policiales en PDF para Carabineros/PDI y manuales de uso ilustrados para adultos mayores.

---

## ⚡ Características Principales

### 🚨 1. Botonera de Alerta Inmediata y Sirena de Potencia
* **4 Niveles de Emergencia:**
  * 🔴 **Robo / Intrusión:** Alarma prioritaria que suena en 1 solo toque sin exigir texto.
  * 🟠 **Incendio:** Aviso sonoro para ataque rápido con extintores y llamado a Bomberos.
  * 🔵 **Accidente Médico:** Alerta de socorro para rescate de adultos mayores o emergencias de salud.
  * 🟢 **Sospechoso:** Notificación disuasiva preventiva para encendido de luces comunitarias.
* **Sonido Infranqueable:** El audio utiliza archivos WAV customizados en loop que elevan el volumen del sistema y disparan el motor de vibración continuo.
* **Despertar de Pantalla (Wakelock):** Fuerza el encendido de pantalla mediante Foreground Task para evitar que el modo Doze de Android silencie la alerta.

### 📞 2. Centrales de Emergencia (1-Toque)
Accesos directos con marcado telefónico instantáneo sin necesidad de recordar ni buscar en la libreta de contactos:
* **🟢 133:** Carabineros de Chile
* **🔴 132:** Bomberos de Chile
* **🔵 131:** SAMU Ambulancia de Urgencia
* **🛡️ 1414:** Seguridad Ciudadana Comunal (Coronel)

### 🏘️ 3. Padrón Vecinal y Gestión de Cupos por Vivienda
* **Esquema de 3 Teléfonos por Hogar:** Cada vivienda registrada cuenta con un cupo base incluido de hasta 3 celulares familiares vinculados a la misma dirección.
* **Cupos Extra ($5.000 CLP):** Los residentes pueden solicitar teléfonos adicionales mediante el abono de una tarifa única de $5.000 por dispositivo extra.
* **Control Centralizado:** Desde el Panel de Administrador se visualizan los residentes por vivienda, con botones dedicados para ampliar cupos con un solo toque una vez confirmado el pago.
* **Seguridad y Control de Identidad:** Limitación de corrección de datos personales (máximo 3 intentos por usuario) para evitar suplantaciones o adulteraciones maliciosas.

### 🚔 4. Generación de Expedientes Policiales en PDF con Código QR
* **Dosier Oficial Automatizado:** Permite al Administrador seleccionar una o múltiples alertas mediante casillas de verificación (checkbox) y exportar un documento PDF consolidado de validez legal.
* **Evidencia Completa:** Incluye:
  * Fecha, hora exacta y duración del evento.
  * Nombre completo del alertante, pasaje y número de casa.
  * Captura satelital del sector afectado con coordenadas GPS (`Lat: -36.9818, Lon: -73.1554`).
  * Galería de fotografías de evidencia capturadas durante el suceso.
* **Código QR Digital:** Genera un QR dinámico para que las patrullas policiales o personal municipal puedan descargar el expediente digital en su propio teléfono en segundos.

### 📖 5. Manuales de Usuario Ilustrados en HD
* **Manual de Vecinos y Adultos Mayores:** Formateado con letra grande, capturas reales de la interfaz de usuario limpia y lenguaje sin tecnicismos para facilitar la adopción comunitaria.
* **Manual Técnico de Administración:** Guía detallada para la directiva sobre cómo gestionar alertas, regular cupos, notificar comunicados oficiales y supervisar el padrón.
* **Exportación PDF:** Ambos manuales pueden visualizarse en pantalla o exportarse/imprimirse directamente a través del motor PDF integrado.

### 🔄 6. Actualizaciones Automáticas en la Nube (OTA)
* La aplicación supervisa automáticamente en segundo plano la existencia de nuevas versiones mediante Firebase Realtime Database.
* Cuando el administrador publica una actualización, los vecinos reciben una tarjeta destacada con las novedades y el botón **"ACTUALIZAR AHORA"**, descargando la nueva versión sin depender de códigos QR ni tiendas externas.
* El aviso se oculta de forma inteligente una vez actualizada la aplicación.

---

## 📂 Estructura del Repositorio

```text
alerta-vecinal/
├── app/                                  # Aplicación móvil completa desarrollada en Flutter
│   ├── android/                          # Configuración nativa de Android, Gradle y Permisos
│   │   └── app/google-services.json      # Configuración de servicios Firebase
│   ├── assets/
│   │   ├── images/                       # Logotipos, íconos y capturas HD para manuales
│   │   └── sounds/                       # Audios WAV de sirenas (robo, incendio, ambulancia)
│   ├── lib/
│   │   ├── models/                       # Modelos de datos (Alertas, Botones, Padrón)
│   │   ├── screens/                      # Pantallas principales:
│   │   │   ├── home_screen.dart          # Vista del vecino, botoneras y emergencias
│   │   │   ├── admin_screen.dart         # Panel administrativo, padrón, cupos y reportes
│   │   │   └── register_screen.dart      # Registro inicial con validación de cupos por casa
│   │   ├── services/                     # Lógica de sincronización, alarmas, PDF y biometría:
│   │   │   ├── alarm_sync_service.dart   # Sincronización en tiempo real con Firebase DB
│   │   │   ├── alarm_player_service.dart # Reproductor nativo de sirenas en bucle
│   │   │   ├── manual_pdf_service.dart   # Generador vectorial de manuales y expedientes PDF
│   │   │   └── biometric_service.dart    # Autenticación por huella/rostro y PIN de seguridad
│   │   └── theme/                        # Paletas de color, temas claro/oscuro y tipografías
│   └── pubspec.yaml                      # Dependencias de Flutter y control de versión
│
├── releases/                             # Directorio de binarios compilados
│   └── AlertaVecinal-Release.apk         # APK compilado de distribución oficial (v1.0.4)
│
├── server/                               # Servidor alternativo en Node.js (WebSocket backup)
│   ├── server.js                         # Servidor ligero para despliegues locales o en Render
│   └── package.json
│
├── cotizacion_alerta_vecinal_las_galileas.html   # Informe ejecutivo interactivo de cotización
├── cotizacion_alerta_vecinal_las_galileas.xlsx   # Planilla financiera detallada en Excel
└── README.md                             # Documentación oficial del proyecto
```

---

## 🛠️ Tecnologías Utilizadas

| Componente | Tecnología | Propósito |
| :--- | :--- | :--- |
| **Frontend Móvil** | [Flutter 3.x](https://flutter.dev/) & [Dart](https://dart.dev/) | Desarrollo multiplataforma con rendimiento nativo de 60 FPS |
| **Backend & Sync** | [Firebase Realtime Database](https://firebase.google.com/) | Sincronización bidireccional en milisegundos con soporte offline |
| **Servicio de Fondo** | [Flutter Foreground Task](https://pub.dev/packages/flutter_foreground_task) | Mantiene el socket de escucha activo con pantalla bloqueada |
| **Audio de Sirena** | [Audioplayers](https://pub.dev/packages/audioplayers) & [Vibration](https://pub.dev/packages/vibration) | Reproducción sonora a volumen máximo y vibración háptica |
| **Generación PDF** | [Pdf](https://pub.dev/packages/pdf) & [Printing](https://pub.dev/packages/printing) | Renderizado vectorial de expedientes policiales y manuales |
| **Cartografía** | [Flutter Map](https://pub.dev/packages/flutter_map) & [LatLong2](https://pub.dev/packages/latlong2) | Visualización y geolocalización de coordenadas del pasaje |
| **Seguridad Admin** | [Local Auth](https://pub.dev/packages/local_auth) | Protección biométrica (huella/rostro) y PIN maestro |

---

## 🚀 Compilación y Despliegue Local

Si deseas compilar la aplicación por tu cuenta:

### Requisitos Previos:
1. Tener instalado [Flutter SDK](https://docs.flutter.dev/get-started/install) (versión 3.29 o superior).
2. Tener configurado el [Android SDK](https://developer.android.com/studio) (Android API 34).
3. Java JDK 17 o superior.

### Pasos:

1. **Clonar el repositorio:**
   ```bash
   git clone https://github.com/ignacio1123/alerta-vecinal-2.git
   cd alerta-vecinal-2/app
   ```

2. **Instalar dependencias de Flutter:**
   ```bash
   flutter pub get
   ```

3. **Verificar que no existan errores estáticos:**
   ```bash
   flutter analyze
   ```

4. **Compilar el archivo APK de Producción:**
   ```bash
   flutter build apk --release
   ```
   El instalador generado se ubicará en:  
   `app/build/app/outputs/flutter-apk/app-release.apk`

---

## 🔒 Privacidad y Seguridad de la Comunidad

1. **Protección de Datos:** Las direcciones y nombres de los residentes se encuentran resguardados bajo reglas declarativas en Firebase Database, permitiendo la visibilidad comunitaria únicamente a los dispositivos suscritos a la red del comité.
2. **Control de Acceso Administrativo:** Las funciones sensibles (habilitación de cupos, eliminación de reportes, desactivación de vecinos y emisión de comunicados) requieren autenticación por **PIN de seguridad de 4 dígitos** o **biometría nativa**.
3. **Respaldo de Emergencia Offline:** Si la conexión a Internet domiciliaria falla temporalmente, la aplicación mantiene en memoria local la caché del padrón y el historial mediante persistencia nativa de Firebase.

---

## 📄 Licencia

Este proyecto se encuentra publicado bajo los términos de la licencia **WTFPL (Do What The Fuck You Want To Public License)**. Eres libre de modificarlo, distribuirlo, adaptarlo y utilizarlo para la seguridad de tu propio vecindario.
