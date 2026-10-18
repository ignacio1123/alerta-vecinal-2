import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/alert_model.dart';
import '../services/alarm_player_service.dart';
import '../services/alarm_sync_service.dart';
import '../services/native_alert_service.dart';
import '../theme/app_theme.dart';

class ActiveAlertView extends StatefulWidget {
  final AlertModel alert;
  final VoidCallback onDismissLocal;

  const ActiveAlertView({
    super.key,
    required this.alert,
    required this.onDismissLocal,
  });

  @override
  State<ActiveAlertView> createState() => _ActiveAlertViewState();
}

class _ActiveAlertViewState extends State<ActiveAlertView> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  bool _isSilenced = false;
  Position? _myLocation;

  @override
  void initState() {
    super.initState();
    final key = AlarmSyncService().getAlertKey(widget.alert);
    _isSilenced = AlarmSyncService().isAlertSilenced(key);
    if (!_isSilenced) {
      AlarmPlayerService().startAlarm(widget.alert.type);
    }
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    Geolocator.getLastKnownPosition().then((pos) {
      if (mounted && pos != null) {
        setState(() => _myLocation = pos);
      }
    });
  }

  @override
  void dispose() {
    AlarmPlayerService().stopAlarm();
    _animController.dispose();
    super.dispose();
  }

  Color _parseColor(String colorHex) {
    try {
      final hex = colorHex.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppColors.alertCrimson;
    }
  }

  Future<void> _openGoogleMaps() async {
    double? lat = widget.alert.latitude;
    double? lng = widget.alert.longitude;
    String loc = widget.alert.customLocation.trim();
    if (loc.isEmpty) {
      loc = widget.alert.location.trim();
    }

    // Si faltan lat/lng, intentar extraerlos del texto de ubicación
    if ((lat == null || lng == null) && loc.isNotEmpty) {
      final parsed = AlertModel.extractCoordinates(loc);
      if (parsed.$1 != null && parsed.$2 != null) {
        lat = parsed.$1;
        lng = parsed.$2;
      }
    }

    final List<Uri> candidateUris = [];

    if (lat != null && lng != null) {
      // 1. Android geo intent directo
      candidateUris.add(Uri.parse('geo:$lat,$lng?q=$lat,$lng(Alerta+Vecinal)'));
      // 2. Google Maps web intent
      candidateUris.add(Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'));
    } else if (loc.startsWith('http://') || loc.startsWith('https://')) {
      final parsedUri = Uri.tryParse(loc);
      if (parsedUri != null) {
        candidateUris.add(parsedUri);
      }
    } else if (loc.isNotEmpty) {
      candidateUris.add(Uri.parse('geo:0,0?q=${Uri.encodeComponent(loc)}'));
      candidateUris.add(Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(loc)}'));
    } else {
      final fallback = AlarmSyncService().fullAddress;
      if (fallback.isNotEmpty) {
        candidateUris.add(Uri.parse('geo:0,0?q=${Uri.encodeComponent(fallback)}'));
        candidateUris.add(Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(fallback)}'));
      }
    }

    if (candidateUris.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay información de ubicación disponible para este incidente.')),
        );
      }
      return;
    }

    bool launched = false;
    for (final uri in candidateUris) {
      try {
        if (await canLaunchUrl(uri)) {
          launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (launched) break;
        }
      } catch (_) {}
    }

    // Fallback con platformDefault
    if (!launched) {
      for (final uri in candidateUris) {
        if (uri.scheme == 'http' || uri.scheme == 'https') {
          try {
            launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
            if (launched) break;
          } catch (_) {}
        }
      }
    }

    // Si aún no abrió, intentar abrir la primera URL web
    if (!launched && candidateUris.isNotEmpty) {
      try {
        launched = await launchUrl(candidateUris.last, mode: LaunchMode.platformDefault);
      } catch (_) {}
    }

    if (!launched && mounted) {
      final copyText = (lat != null && lng != null) ? '$lat, $lng' : loc;
      if (copyText.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: copyText));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange.shade800,
          content: Text(
            copyText.isNotEmpty
                ? 'No se pudo abrir Maps directamente. Coordenadas copiadas al portapapeles: $copyText'
                : 'No se pudo abrir la aplicación de mapas.',
          ),
        ),
      );
    }
  }

  Future<void> _promptUpdateDescription() async {
    final ctrl = TextEditingController(text: widget.alert.description);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit_note, color: Colors.deepOrange),
            SizedBox(width: 8),
            Text('Detalle de lo Sucedido', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Escribe o actualiza los detalles de lo que está ocurriendo para que los vecinos y autoridades sepan qué pasó:',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Ej. Sujeto saltando pandereta, auto sospechoso gris...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar y Notificar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok == true && ctrl.text.trim().isNotEmpty) {
      await AlarmSyncService().updateEmergencyAlertDescription(ctrl.text.trim());
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Detalle del reporte actualizado en la red.')),
        );
      }
    }
  }

  Future<void> _sharePhotosViaWhatsApp() async {
    final service = AlarmSyncService();
    final wpNumber = await service.getAdminWhatsApp();
    final cleanPhone = wpNumber.replaceAll(RegExp(r'[^0-9]'), '');

    final now = widget.alert.timestamp;
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(now);
    final code = widget.alert.reportCode.isNotEmpty
        ? widget.alert.reportCode
        : '#REP-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final alertType = widget.alert.type;
    final desc = widget.alert.notes.isNotEmpty ? widget.alert.notes : 'Evidencia registrada por residente';
    final coords = (widget.alert.latitude != null && widget.alert.longitude != null)
        ? '${widget.alert.latitude}, ${widget.alert.longitude}'
        : (widget.alert.customLocation.isNotEmpty ? widget.alert.customLocation : widget.alert.location);

    final cleanCode = code.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    final syncLink = 'https://alerta-vecinal.web.app/reporte?id=$cleanCode';

    final text = '🚨 *EVIDENCIA DE EMERGENCIA VECINAL* 🚨\n'
        '━━━━━━━━━━━━━━━━━━━━━\n'
        '📋 *Reporte ID:* $code\n'
        '⏰ *Fecha y Hora:* $dateStr\n'
        '⚠️ *Tipo de Alerta:* $alertType\n'
        '👤 *Vecino Emisor:* ${widget.alert.sender}\n'
        '📍 *Ubicación / Coordenadas:* $coords\n'
        '📝 *Detalle:* $desc\n'
        '📸 *Evidencia Adjunta:* ${widget.alert.photoCount} fotografía(s) tomada(s)\n'
        '━━━━━━━━━━━━━━━━━━━━━\n'
        '🔗 *Link Carga Automática al Reporte:* $syncLink\n\n'
        '_Estimado(a) Administrador(a), le hago llegar estas fotografías como evidencia para las autoridades policiales correspondientes._';

    if (cleanPhone.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: cleanPhone));
    }

    final localPhotoPaths = await service.getReportPhotos(widget.alert.id, reportCode: widget.alert.reportCode);
    final validFiles = localPhotoPaths
        .map((p) => XFile(p))
        .where((xf) => File(xf.path).existsSync())
        .toList();

    bool sentDirect = false;
    if (cleanPhone.isNotEmpty) {
      sentDirect = await NativeAlertService.shareWhatsAppDirect(
        phone: cleanPhone,
        text: text,
        imagePaths: validFiles.map((f) => f.path).toList(),
      );
    }

    if (sentDirect) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF10B981),
            content: Text('¡Abriendo chat de WhatsApp del Administrador con las fotos y texto!'),
          ),
        );
      }
      return;
    }

    if (validFiles.isNotEmpty) {
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: validFiles,
            text: text,
            subject: '🚨 Evidencia Alerta Vecinal - $code',
          ),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              content: Text(cleanPhone.isNotEmpty
                  ? '¡Fotos preparadas con texto abajo! Elige WhatsApp para enviar (Admin: +$cleanPhone copiado).'
                  : '¡Fotos preparadas con texto abajo! Elige la app para enviar.'),
            ),
          );
        }
        return;
      } catch (_) {}
    }

    Uri uri;
    if (cleanPhone.isNotEmpty) {
      uri = Uri.parse('whatsapp://send?phone=$cleanPhone&text=${Uri.encodeComponent(text)}');
    } else {
      uri = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(text)}');
    }

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        final webUri = Uri.parse('https://wa.me/$cleanPhone?text=${Uri.encodeComponent(text)}');
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir WhatsApp: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm:ss').format(widget.alert.timestamp);
    final accentColor = _parseColor(widget.alert.color);
    final hasCoords = widget.alert.latitude != null && widget.alert.longitude != null;
    final service = AlarmSyncService();
    final canCancelGeneral = service.isAdmin || widget.alert.sender.contains(service.fullName);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        AlarmPlayerService().stopAlarm();
        final key = service.getAlertKey(widget.alert);
        service.markAlertDismissed(key);
        widget.onDismissLocal();
      },
      child: Scaffold(
        backgroundColor: accentColor.withValues(alpha: 0.08),
        body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 90 + MediaQuery.of(context).padding.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),

              // Animated Pulsing Icon
              Center(
                child: AnimatedBuilder(
                  animation: _animController,
                  builder: (context, child) {
                    final scale = 1.0 + (_animController.value * 0.12);
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withValues(alpha: 0.45),
                              blurRadius: 28 * scale,
                              spreadRadius: 6 * scale,
                            ),
                          ],
                        ),
                        child: Text(
                          widget.alert.icon,
                          style: const TextStyle(fontSize: 48),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // Title
              Text(
                '¡${widget.alert.type.toUpperCase()}!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  color: accentColor,
                  letterSpacing: 0.5,
                ),
              ),

              const SizedBox(height: 16),

              // Tarjeta informativa del incidente
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: accentColor.withValues(alpha: 0.4), width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Emisor
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.person_pin_circle,
                            color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF93C5FD) : AppColors.brandNavy,
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'ALERTA EMITIDA POR:',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.alert.sender,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            timeStr,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted),
                          ),
                        ],
                      ),

                      // Descripción completa con opción de edición/actualización en vivo
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.notes, size: 18, color: AppColors.textSecondaryOf(context)),
                              const SizedBox(width: 6),
                              Text(
                                'Descripción del incidente:',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondaryOf(context)),
                              ),
                            ],
                          ),
                          InkWell(
                            onTap: _promptUpdateDescription,
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Row(
                                children: [
                                  const Icon(Icons.edit, size: 13, color: AppColors.steelBlue),
                                  const SizedBox(width: 3),
                                  Text(
                                    widget.alert.description.isEmpty ? 'Escribir detalle' : 'Editar detalle',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.steelBlue),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E222A) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF333B48) : Colors.grey.shade300,
                          ),
                        ),
                        child: Text(
                          widget.alert.description.isNotEmpty
                              ? widget.alert.description
                              : 'Sin descripción aún. Toca "Escribir detalle" para detallar lo sucedido a los vecinos.',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            fontStyle: widget.alert.description.isEmpty ? FontStyle.italic : FontStyle.normal,
                            color: widget.alert.description.isNotEmpty
                                ? AppColors.textPrimaryOf(context)
                                : AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ),

                      // Ubicación e incidente
                      if (hasCoords || widget.alert.customLocation.isNotEmpty || widget.alert.location.isNotEmpty) ...[
                        const Divider(height: 24),
                        Row(
                          children: [
                            Icon(Icons.location_on, size: 18, color: accentColor),
                            const SizedBox(width: 6),
                            Text(
                              'Ubicación del incidente:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondaryOf(context)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Dirección o Coordenadas en texto legible con botón de copiar
                        Builder(
                          builder: (context) {
                            final locText = widget.alert.customLocation.isNotEmpty
                                ? widget.alert.customLocation
                                : (widget.alert.location.isNotEmpty
                                    ? widget.alert.location
                                    : (hasCoords
                                        ? '${widget.alert.latitude!.toStringAsFixed(5)}, ${widget.alert.longitude!.toStringAsFixed(5)}'
                                        : 'Ubicación comunitaria'));
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF1E222A)
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? const Color(0xFF333B48)
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      locText,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimaryOf(context),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 18),
                                    tooltip: 'Copiar ubicación',
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: locText));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Ubicación copiada al portapapeles.'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 10),

                        // Mapa visual interactivo real (CartoDB Voyager)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: double.infinity,
                            height: 185,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF333B48)
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Stack(
                              children: [
                                FlutterMap(
                                  options: MapOptions(
                                    initialCenter: latlong.LatLng(
                                      widget.alert.latitude ?? -36.9568766,
                                      widget.alert.longitude ?? -73.1517670,
                                    ),
                                    initialZoom: 17.5,
                                    minZoom: 13.0,
                                    maxZoom: 19.0,
                                    interactionOptions: const InteractionOptions(
                                      flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                                    ),
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName: 'com.comunidad.alerta.alerta_vecinal_app',
                                      maxZoom: 19,
                                    ),
                                    MarkerLayer(
                                      markers: [
                                        if (_myLocation != null)
                                          Marker(
                                            point: latlong.LatLng(
                                              _myLocation!.latitude,
                                              _myLocation!.longitude,
                                            ),
                                            width: 65,
                                            height: 55,
                                            alignment: Alignment.topCenter,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF1D4ED8),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Text(
                                                    '📱 Tú',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 8.5,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  width: 22,
                                                  height: 22,
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue.shade600,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(color: Colors.white, width: 2),
                                                    boxShadow: const [BoxShadow(color: Colors.blueAccent, blurRadius: 4)],
                                                  ),
                                                  child: const Icon(Icons.person, color: Colors.white, size: 14),
                                                ),
                                              ],
                                            ),
                                          ),
                                        Marker(
                                          point: latlong.LatLng(
                                            widget.alert.latitude ?? -36.9568766,
                                            widget.alert.longitude ?? -73.1517670,
                                          ),
                                          width: 50,
                                          height: 50,
                                          alignment: Alignment.topCenter,
                                          child: const Icon(
                                            Icons.location_on,
                                            color: Colors.redAccent,
                                            size: 42,
                                            shadows: [
                                              Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                // Badge flotante informativo
                                Positioned(
                                  bottom: 8,
                                  left: 8,
                                  right: 8,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.8),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.touch_app, size: 13, color: Colors.white),
                                          const SizedBox(width: 4),
                                          Text(
                                            hasCoords
                                                ? 'GPS: ${widget.alert.latitude!.toStringAsFixed(5)}, ${widget.alert.longitude!.toStringAsFixed(5)}'
                                                : 'Ubicación Comunitaria',
                                            style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Botón de abrir en Google Maps
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.steelBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 2,
                            ),
                            onPressed: _openGoogleMaps,
                            icon: const Icon(Icons.map, size: 20),
                            label: const Text('ABRIR EN GOOGLE MAPS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                          ),
                        ),
                      ],

                      // Aviso de Fotos registradas
                      if (widget.alert.photoCount > 0) ...[
                        const Divider(height: 24),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E293B) : Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF3B82F6) : Colors.indigo.shade200,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.photo_camera_back,
                                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF93C5FD) : AppColors.brandNavy,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '📷 EVIDENCIA FOTOGRÁFICA (${widget.alert.photoCount} FOTOS)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF93C5FD) : AppColors.brandNavy,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'El vecino registró fotos en su dispositivo como respaldo. Serán enviadas al Administrador vía WhatsApp y a las autoridades policiales.',
                                      style: TextStyle(fontSize: 12, color: AppColors.textPrimaryOf(context), height: 1.3),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF25D366),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _sharePhotosViaWhatsApp,
                            icon: const Icon(Icons.send, size: 18),
                            label: const Text(
                              'Enviar Fotos al Admin (WhatsApp)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Mensaje de Precaución para los vecinos
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF33230A) : Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.amber.shade700 : Colors.amber.shade400,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.shield_outlined, color: Colors.deepOrange, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '⚠️ ADVERTENCIA DE SEGURIDAD',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.amber.shade200 : Colors.deepOrange,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Si te encuentras solo(a), NO intervengas directamente. Prioriza tu seguridad personal, mantén distancia prudente, verifica desde un lugar seguro y espera la llegada de Carabineros o más vecinos.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.amber.shade100 : const Color(0xFF78350F),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Acciones
              // 1. Silenciar Sirena en mi teléfono (mantiene la pantalla fija)
              ElevatedButton.icon(
                onPressed: _isSilenced
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final alertKey = service.getAlertKey(widget.alert);
                        await service.markAlertSilenced(alertKey);
                        if (!mounted) return;
                        setState(() {
                          _isSilenced = true;
                        });
                        messenger.showSnackBar(
                          const SnackBar(
                            backgroundColor: Color(0xFF059669),
                            content: Row(
                              children: [
                                Icon(Icons.volume_off, color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Sirena silenciada en este equipo. La información permanece en pantalla.',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                  ),
                                ),
                              ],
                            ),
                            duration: Duration(seconds: 4),
                          ),
                        );
                      },
                icon: Icon(_isSilenced ? Icons.check_circle : Icons.volume_off, color: Colors.white),
                label: Text(
                  _isSilenced ? 'Sirena Silenciada en Este Dispositivo' : 'Silenciar Sirena en Mi Teléfono',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: _isSilenced
                      ? Colors.grey.shade600
                      : (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2563EB) : AppColors.brandNavy),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),

              // 2. Apagar Alarma para Todos los Dispositivos (Solo Admin o el residente que la emitió)
              if (canCancelGeneral) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    final alertKey = service.getAlertKey(widget.alert);
                    await service.markAlertDismissed(alertKey);
                    await service.cancelEmergencyAlert();
                    widget.onDismissLocal();
                  },
                  icon: const Icon(Icons.alarm_off, color: Colors.white, size: 22),
                  label: const Text(
                    'Apagar Alarma para Todos los Dispositivos',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    textAlign: TextAlign.center,
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: AppColors.alertCrimson,
                    foregroundColor: Colors.white,
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // 3. Salir / Cerrar Aviso (Permite al vecino o admin salir manualmente cuando ya leyó)
              OutlinedButton.icon(
                onPressed: () async {
                  final alertKey = service.getAlertKey(widget.alert);
                  await service.markAlertDismissed(alertKey);
                  widget.onDismissLocal();
                },
                icon: Icon(
                  Icons.close,
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : AppColors.brandNavy,
                ),
                label: Text(
                  'Cerrar Aviso / Salir',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.brandNavy,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white38 : AppColors.brandNavy.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkCard : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    ),
  );
}
}
