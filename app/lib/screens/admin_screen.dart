import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/alert_model.dart';
import '../models/neighborhood_locations.dart';
import '../services/alarm_sync_service.dart';
import '../services/manual_pdf_service.dart';
import '../services/map_snapshot_service.dart';
import '../services/native_alert_service.dart';
import '../theme/app_theme.dart';
import 'register_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  final service = AlarmSyncService();
  late TabController _tabController;

  // Filtro de reportes y selección múltiple para impresión
  String _reportFilter = 'semana'; // 'semana', 'mes', 'anio', 'todos'
  final Set<String> _selectedReportIds = {};

  // Herramientas de Sistema
  final _whatsappCtrl = TextEditingController();
  final _qrUrlCtrl = TextEditingController();
  final _seguridadPhoneCtrl = TextEditingController();
  final _comunicadoTituloCtrl = TextEditingController();
  final _comunicadoMensajeCtrl = TextEditingController();
  final _updateVersionCtrl = TextEditingController(text: '1.0.2');
  final _updateNotesCtrl = TextEditingController(text: 'Mejoras de rendimiento y optimización de alarmas.');
  bool _showQr = true;
  bool _isIgnoringBattery = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadSystemConfig();
  }

  Future<void> _loadSystemConfig() async {
    final wp = await service.getAdminWhatsApp();
    final qr = await service.getApkDownloadUrl();
    final seg = await service.getSeguridadCiudadanaPhone();
    final bat = await NativeAlertService.isIgnoringBatteryOptimizations();
    final notice = await service.getLatestCommunityNotice();
    final updateInfo = await service.getLatestAppUpdateInfo();
    if (mounted) {
      setState(() {
        _whatsappCtrl.text = wp;
        _qrUrlCtrl.text = qr;
        _seguridadPhoneCtrl.text = seg;
        if (notice != null) {
          _comunicadoTituloCtrl.text = notice['titulo'] ?? '';
          _comunicadoMensajeCtrl.text = notice['mensaje'] ?? '';
        }
        if (updateInfo != null) {
          final lastVer = updateInfo['versionName'] ?? '1.0.3';
          _updateVersionCtrl.text = _incrementVersion(lastVer.toString());
          final notes = updateInfo['notes']?.toString().trim();
          _updateNotesCtrl.text = (notes != null && notes.isNotEmpty) ? notes : _getDefaultImprovementNotes();
        } else {
          _updateVersionCtrl.text = '1.0.4';
          _updateNotesCtrl.text = _getDefaultImprovementNotes();
        }
        _isIgnoringBattery = bat;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _whatsappCtrl.dispose();
    _qrUrlCtrl.dispose();
    _seguridadPhoneCtrl.dispose();
    _comunicadoTituloCtrl.dispose();
    _comunicadoMensajeCtrl.dispose();
    _updateVersionCtrl.dispose();
    _updateNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _triggerTestAlert() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Disparar Alarma de Prueba'),
        content: const Text(
          'Esto enviará una señal de emergencia de prueba a TODOS los teléfonos de los vecinos conectados. ¿Continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DISPARAR PRUEBA', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await service.sendEmergencyAlert(
        type: 'PRUEBA DE SISTEMA',
        description: 'Prueba emitida desde el panel administrador',
        location: 'Comunidad',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alarma de prueba enviada con éxito.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error al emitir prueba: $e')),
        );
      }
    }
  }

  Future<void> _cancelActiveAlert() async {
    await service.cancelEmergencyAlert();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alerta cancelada en toda la red.')),
      );
    }
  }

  List<Map<String, dynamic>> _filterReports(List<Map<String, dynamic>> all) {
    if (_reportFilter == 'todos') return all;

    final now = DateTime.now();
    DateTime threshold;
    if (_reportFilter == 'semana') {
      threshold = now.subtract(const Duration(days: 7));
    } else if (_reportFilter == 'mes') {
      threshold = now.subtract(const Duration(days: 30));
    } else {
      threshold = DateTime(now.year, 1, 1);
    }

    return all.where((r) {
      final raw = r['timestamp'];
      if (raw is num) {
        final d = DateTime.fromMillisecondsSinceEpoch(raw.toInt());
        return d.isAfter(threshold);
      }
      return true;
    }).toList();
  }

  Future<void> _exportPdfReport(List<Map<String, dynamic>> filtered) async {
    final filterTitle = _reportFilter == 'semana'
        ? 'ÚLTIMA SEMANA'
        : (_reportFilter == 'mes'
            ? 'ÚLTIMO MES'
            : (_reportFilter == 'anio' ? 'AÑO ${DateTime.now().year}' : 'HISTORIAL COMPLETO'));
    await _printReportsDossier(filtered, title: 'REPORTE POLICIAL CONSOLIDADO: $filterTitle', directPrint: false);
  }

  Future<List<String>> _getReportPhotos(String reportId, {String? reportCode}) =>
      service.getReportPhotos(reportId, reportCode: reportCode);

  Future<void> _attachReportPhoto(String reportId, ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (picked == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${dir.path}/evidence_photos');
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }
      final fileName = 'evidence_${reportId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedFile = await File(picked.path).copy('${photosDir.path}/$fileName');

      await service.addReportPhoto(reportId, savedFile.path);
      await service.syncReportPhotoToFirebase(reportId, savedFile.path);

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📷 Foto adjuntada con éxito. Se incluirá en el PDF para Carabineros.'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al adjuntar foto: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _removeReportPhoto(String reportId, String path) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar foto'),
        content: const Text('¿Deseas desvincular esta fotografía de este reporte?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await service.removeReportPhoto(reportId, path);
      try {
        final f = File(path);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
      if (mounted) setState(() {});
    }
  }

  void _showAttachPhotoSheet(String reportId, String reportCode) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.add_a_photo, color: AppColors.steelBlue, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Adjuntar Evidencia ($reportCode)',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Las fotografías se guardan localmente y se incrustan en el expediente PDF para las autoridades, sin ocupar servidores ni costo adicional.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(ctx)),
              ),
              const Divider(height: 20),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF2563EB),
                  child: Icon(Icons.camera_alt, color: Colors.white, size: 20),
                ),
                title: const Text('Tomar fotografía en el momento', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                subtitle: const Text('Usar cámara en vivo en el lugar del incidente', style: TextStyle(fontSize: 11.5)),
                onTap: () {
                  Navigator.pop(ctx);
                  _attachReportPhoto(reportId, ImageSource.camera);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF10B981),
                  child: Icon(Icons.photo_library, color: Colors.white, size: 20),
                ),
                title: const Text('Elegir de Galería / WhatsApp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                subtitle: const Text('Seleccionar fotos recibidas del vecino por chat', style: TextStyle(fontSize: 11.5)),
                onTap: () {
                  Navigator.pop(ctx);
                  _attachReportPhoto(reportId, ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _viewFullPhoto(String path, String reportCode) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text('Evidencia: $reportCode', style: const TextStyle(fontSize: 14)),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            InteractiveViewer(
              maxScale: 4.0,
              child: Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No se pudo cargar la imagen.'),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  (double? lat, double? lng, String address, String mapsUrl) _resolveReportLocation(Map<String, dynamic> r) {
    double? lat = (r['latitude'] as num?)?.toDouble();
    double? lng = (r['longitude'] as num?)?.toDouble();

    String customLoc = '${r['ubicacionIncidente'] ?? r['customLocation'] ?? ''}'.trim();
    String mainLoc = '${r['ubicacion'] ?? r['location'] ?? ''}'.trim();

    // Si no hay lat/lng numérico, intentar extraerlo del texto de customLoc o mainLoc
    if (lat == null || lng == null) {
      if (customLoc.isNotEmpty) {
        final parsed = AlertModel.extractCoordinates(customLoc);
        lat = parsed.$1;
        lng = parsed.$2;
      }
      if ((lat == null || lng == null) && mainLoc.isNotEmpty) {
        final parsed = AlertModel.extractCoordinates(mainLoc);
        lat = parsed.$1;
        lng = parsed.$2;
      }
    }

    // Determinar texto visible de dirección
    String displayAddress = customLoc.isNotEmpty
        ? customLoc
        : (mainLoc.isNotEmpty ? mainLoc : (service.fullAddress.isNotEmpty ? service.fullAddress : 'Sector Coronel'));

    // Construir URL precisa de Google Maps
    String mapsUrl;
    if (lat != null && lng != null) {
      mapsUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    } else {
      // Coordenadas base reales de Villa Escuadrón Galilea (Praderas de Coronel, Biobío)
      lat = -36.97025;
      lng = -73.13600;
      mapsUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    }

    return (lat, lng, displayAddress, mapsUrl);
  }

  Future<Uint8List> _generateIncidentMapImage({
    double? lat,
    double? lng,
    required String address,
    required String incidentType,
    required String code,
  }) async {
    final useLat = lat ?? -36.9568766;
    final useLng = lng ?? -73.1517670;
    return MapSnapshotService.generateRealisticMapSnapshot(
      lat: useLat,
      lng: useLng,
      address: address,
      incidentType: incidentType,
      code: code,
    );
  }

  Future<void> _printReportsDossier(
    List<Map<String, dynamic>> reports, {
    required String title,
    bool directPrint = false,
  }) async {
    if (reports.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay incidentes para imprimir o exportar.')),
      );
      return;
    }

    try {
      // Recolectar fotos adjuntas localmente para los reportes a imprimir
      final Map<String, List<Uint8List>> reportPhotosMap = {};
      for (final r in reports) {
        final rid = '${r['id']}';
        final rCode = '${r['codigoReporte'] ?? r['reportCode'] ?? ''}';
        try {
          await service.syncReportPhotosFromCloud(rid, rCode);
        } catch (_) {}
        final paths = await _getReportPhotos(rid, reportCode: rCode);
        final List<Uint8List> bytesList = [];
        for (final p in paths) {
          try {
            final f = File(p);
            if (await f.exists()) {
              bytesList.add(await f.readAsBytes());
            }
          } catch (_) {}
        }
        if (bytesList.isNotEmpty) {
          reportPhotosMap[rid] = bytesList;
        }
      }

      // Generar imagen del mapa visual y URL satelital para el incidente principal
      Uint8List? incidentMapBytes;
      String? incidentMapsUrl;
      double? incidentLat;
      double? incidentLng;
      String? incidentAddress;

      if (reports.isNotEmpty) {
        final loc = _resolveReportLocation(reports.first);
        incidentLat = loc.$1;
        incidentLng = loc.$2;
        incidentAddress = loc.$3;
        incidentMapsUrl = loc.$4;

        try {
          incidentMapBytes = await _generateIncidentMapImage(
            lat: incidentLat,
            lng: incidentLng,
            address: incidentAddress,
            incidentType: reports.first['tipo'] ?? 'Emergencia',
            code: '${reports.first['codigoReporte'] ?? reports.first['reportCode'] ?? '#REP'}',
          );
        } catch (_) {}
      }

      final pdf = pw.Document();
      final rows = reports.map((r) {
        final rid = '${r['id']}';
        final raw = r['timestamp'];
        String dateStr = '-';
        if (raw is num) {
          dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(raw.toInt()));
        }
        final code = '${r['codigoReporte'] ?? r['reportCode'] ?? '#REP'}';
        final tipo = '${r['tipo'] ?? 'Emergencia'}';
        final emisor = '${r['emisor'] ?? ''}';
        final desc = '${r['descripcion'] ?? ''}';
        final localPhotosCount = reportPhotosMap[rid]?.length ?? 0;
        final basePhotos = r['fotosTomadas'] != null && r['fotosTomadas'] > 0 ? (r['fotosTomadas'] as num).toInt() : 0;
        final totalFotos = basePhotos + localPhotosCount;
        final fotos = totalFotos > 0 ? '\n[📷 $totalFotos foto(s)]' : '';
        final ubic = '${r['ubicacion'] ?? ''}$fotos';
        return [code, dateStr, tipo, emisor, desc, ubic];
      }).toList();

      final firstUbic = reports.first['ubicacion'] ?? '';
      final qrContent = incidentMapsUrl ??
          (firstUbic.toString().isNotEmpty
              ? 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(firstUbic.toString())}'
              : 'CENTINELA URBANO - Total incidentes: ${reports.length}');

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (ctx) => [
            // Membrete Oficial Policial / Comunitario
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('CENTINELA URBANO — SISTEMA DE ALERTA VECINAL',
                          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                      pw.Text('ACTA COMUNITARIA DE ANTECEDENTES Y DENUNCIA POLICIAL',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.red700,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text('USO OFICIAL',
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 3),
                      pw.Text('Fecha de emisión: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                      pw.Text('Eventos adjuntos: ${reports.length} incidente(s) verificado(s) por la comunidad',
                          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                      pw.Text('Denunciante / Administrador: ${service.fullName.isNotEmpty ? service.fullName : 'Administrador Comunitario'}',
                          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(3),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
                  child: pw.Column(
                    children: [
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: qrContent,
                        width: 50,
                        height: 50,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text('Escanear Mapa', style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey800)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: ['ID Reporte', 'Fecha/Hora', 'Tipo', 'Emisor / Vivienda', 'Detalles', 'Ubicación / Fotos'],
              data: rows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8.5),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              cellAlignment: pw.Alignment.topLeft,
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
            ),
            // CROQUIS Y PLANIMETRÍA DEL INCIDENTE (Mapa visual + QR satelital)
            if (incidentMapBytes != null && incidentMapsUrl != null) ...[
              pw.SizedBox(height: 12),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.indigo900, width: 1.2),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'CROQUIS Y LOCALIZACIÓN GEOGRÁFICA DEL INCIDENTE',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: PdfColors.indigo900),
                        ),
                        pw.Text(
                          (incidentLat != null && incidentLng != null)
                              ? 'GPS: ${incidentLat.toStringAsFixed(5)}°, ${incidentLng.toStringAsFixed(5)}°'
                              : 'REFERENCIA COMUNITARIA',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.red800),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          flex: 3,
                          child: pw.ClipRRect(
                            horizontalRadius: 4,
                            verticalRadius: 4,
                            child: pw.Image(
                              pw.MemoryImage(incidentMapBytes),
                              height: 125,
                              fit: pw.BoxFit.contain,
                            ),
                          ),
                        ),
                        pw.SizedBox(width: 10),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Text('ACCESO DIGITAL SATELITAL',
                                  style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                              pw.SizedBox(height: 4),
                              pw.BarcodeWidget(
                                barcode: pw.Barcode.qrCode(),
                                data: incidentMapsUrl,
                                width: 75,
                                height: 75,
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                'Escanear con cámara para abrir navegación satelital (Google Maps / Waze).',
                                textAlign: pw.TextAlign.center,
                                style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey800),
                              ),
                              pw.SizedBox(height: 3),
                              pw.UrlLink(
                                destination: incidentMapsUrl,
                                child: pw.Text(
                                  'Clic aquí para abrir mapa interactivo',
                                  style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.blue800, decoration: pw.TextDecoration.underline),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('Punto de referencia / Dirección: ${incidentAddress ?? "Sector Coronel"}',
                        style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800)),
                  ],
                ),
              ),
            ],
            if (reportPhotosMap.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const pw.BoxDecoration(color: PdfColors.indigo900),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'ANEXO DE EVIDENCIA FOTOGRÁFICA REGISTRADA',
                      style: pw.TextStyle(color: PdfColors.white, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      'RESGUARDO PERICIAL DE SEGURIDAD VECINAL',
                      style: const pw.TextStyle(color: PdfColors.white, fontSize: 7.5),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Fotografías vinculadas al incidente como evidencia pericial para Carabineros o Fiscalía:',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 8),
              ...reportPhotosMap.entries.expand((entry) {
                final rid = entry.key;
                final rMatch = reports.firstWhere((e) => '${e['id']}' == rid, orElse: () => <String, dynamic>{});
                final code = '${rMatch['codigoReporte'] ?? rMatch['reportCode'] ?? '#REP-$rid'}';
                final tipo = '${rMatch['tipo'] ?? 'Emergencia'}';
                final emisor = '${rMatch['emisor'] ?? ''}';
                final desc = '${rMatch['descripcion'] ?? ''}';
                final images = entry.value;

                return [
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                    child: pw.Text(
                      'EVIDENCIA DE REPORTE $code ($tipo - $emisor)${desc.isNotEmpty ? " • Detalle: $desc" : ""}',
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                    ),
                  ),
                  pw.Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: images.asMap().entries.map((entry) {
                      final idx = entry.key + 1;
                      final imgBytes = entry.value;
                      return pw.Container(
                        width: 155,
                        height: 120,
                        padding: const pw.EdgeInsets.all(3),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
                          borderRadius: pw.BorderRadius.circular(4),
                          color: PdfColors.white,
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Expanded(
                              child: pw.ClipRRect(
                                horizontalRadius: 3,
                                verticalRadius: 3,
                                child: pw.Image(
                                  pw.MemoryImage(imgBytes),
                                  fit: pw.BoxFit.contain,
                                ),
                              ),
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text('Evidencia Fotográfica #$idx',
                                style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ];
              }),
            ],
            pw.SizedBox(height: 24),
            // Cuadro de firmas para entrega a Carabineros / Autoridades
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      pw.Container(height: 1, color: PdfColors.grey800),
                      pw.SizedBox(height: 4),
                      pw.Text('Firma Administrador / Denunciante',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Comité de Seguridad Vecinal', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                    ],
                  ),
                ),
                pw.SizedBox(width: 35),
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      pw.Container(height: 1, color: PdfColors.grey800),
                      pw.SizedBox(height: 4),
                      pw.Text('Recepción Carabineros / PDI / Seguridad',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Timbre y Firma de Guardia Policial', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      final pdfBytes = await pdf.save();

      if (directPrint) {
        await Printing.layoutPdf(
          onLayout: (format) async => pdfBytes,
          name: 'Expediente_Policial_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
        );
      } else {
        await Printing.sharePdf(
          bytes: pdfBytes,
          filename: 'Expediente_Policial_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al procesar documento: $e')),
        );
      }
    }
  }

  void _showReportQrDialog(Map<String, dynamic> r) {
    final code = '${r['codigoReporte'] ?? r['reportCode'] ?? '#REP-${r['id']}'}';
    final tipo = '${r['tipo'] ?? 'Emergencia'}';
    final emisor = '${r['emisor'] ?? 'Desconocido'}';
    final rawTime = r['timestamp'];
    String dateStr = '-';
    if (rawTime is num) {
      dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(rawTime.toInt()));
    }
    final desc = '${r['descripcion'] ?? ''}';
    final fotos = r['fotosTomadas'] ?? 0;

    final (lat, lng, displayAddress, mapsUrl) = _resolveReportLocation(r);

    final String fichaText = '🚨 ACTA OFICIAL DE SEGURIDAD VECINAL\n'
        'Folio: $code\n'
        'Tipo: $tipo\n'
        'Emisor: $emisor\n'
        'Fecha: $dateStr\n'
        'Ubicación: $displayAddress\n'
        '${lat != null && lng != null ? "Coordenadas: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}\n" : ""}'
        '${desc.isNotEmpty ? "Detalle: $desc\n" : ""}'
        'Evidencia: $fotos foto(s)\n'
        'Mapa GPS: $mapsUrl';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    int qrMode = 0; // 0 = Ficha Oficial / PDF, 1 = Navegación Satelital (Maps)

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final qrPayload = qrMode == 0 ? fichaText : mapsUrl;

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.qr_code_2, color: AppColors.steelBlue, size: 26),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'QR y Ficha de Incidente ($code)',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        label: Text('Ficha Oficial', style: TextStyle(fontSize: 11)),
                        icon: Icon(Icons.description, size: 14),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text('GPS / Maps', style: TextStyle(fontSize: 11)),
                        icon: Icon(Icons.location_on, size: 14),
                      ),
                    ],
                    selected: {qrMode},
                    onSelectionChanged: (set) => setDialogState(() => qrMode = set.first),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E2B3E) : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? const Color(0xFF2563EB).withValues(alpha: 0.3) : Colors.blue.shade200,
                      ),
                    ),
                    child: Text(
                      qrMode == 0
                          ? 'Al escanear este QR se leerán los antecedentes policiales del reporte ($code). Para enviar o descargar el archivo PDF completo con fotos y plano, pulsa el botón naranja "Generar PDF".'
                          : 'Al escanear este QR se abrirá automáticamente la ubicación satelital verificada en Google Maps / Waze con coordenadas exactas.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? const Color(0xFF93C5FD) : AppColors.brandNavy,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: QrImageView(
                      data: qrPayload,
                      version: QrVersions.auto,
                      size: 190,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _printReportsDossier(
                          [r],
                          title: 'FICHA INDIVIDUAL DE INCIDENTE - $code',
                          directPrint: false,
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf, size: 18),
                      label: const Text(
                        'GENERAR Y COMPARTIR PDF',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isDark ? AppColors.darkBorder : Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('📋 $code  •  $tipo', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                        const SizedBox(height: 3),
                        Text('👤 Emisor: $emisor', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondaryOf(ctx))),
                        Text('⏰ Fecha: $dateStr', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondaryOf(ctx))),
                        Text('📍 Dirección: $displayAddress', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondaryOf(ctx))),
                        if (lat != null && lng != null)
                          Text('🌐 GPS: ${lat.toStringAsFixed(5)}°, ${lng.toStringAsFixed(5)}°',
                              style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w600)),
                        if (desc.isNotEmpty)
                          Text('📝 Detalle: $desc', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondaryOf(ctx))),
                        if (fotos is num && fotos > 0)
                          Text('📷 Evidencia: $fotos foto(s) registradas',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.blue)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<List<String>>(
                    future: _getReportPhotos('${r['id']}', reportCode: '${r['codigoReporte'] ?? r['reportCode'] ?? ''}'),
                    builder: (photoCtx, photoSnap) {
                      final pList = photoSnap.data ?? [];
                      if (pList.isEmpty) {
                        return OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showAttachPhotoSheet('${r['id']}', code);
                          },
                          icon: const Icon(Icons.add_a_photo, size: 16),
                          label: const Text('Adjuntar fotografía a este reporte', style: TextStyle(fontSize: 11.5)),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '📷 Fotografías adjuntas (${pList.length}):',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _showAttachPhotoSheet('${r['id']}', code);
                                },
                                icon: const Icon(Icons.add_a_photo, size: 14),
                                label: const Text('Agregar más', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 65,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: pList.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 8),
                              itemBuilder: (_, idx) {
                                final f = File(pList[idx]);
                                return GestureDetector(
                                  onTap: () => _viewFullPhoto(pList[idx], code),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      width: 65,
                                      height: 65,
                                      color: Colors.black12,
                                      child: f.existsSync()
                                          ? Image.file(f, fit: BoxFit.cover)
                                          : const Icon(Icons.broken_image, size: 20),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  final uri = Uri.tryParse(mapsUrl);
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.map, size: 16),
                label: const Text('Abrir Maps', style: TextStyle(fontSize: 12)),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _printReportsDossier([r], title: 'FICHA INDIVIDUAL DE INCIDENTE - $code', directPrint: true);
                },
                icon: const Icon(Icons.print, size: 16),
                label: const Text('Imprimir', style: TextStyle(fontSize: 12)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showBatchReportsQrDialog(
    List<Map<String, dynamic>> reports,
    String filterKey, {
    bool autoDownloadPdf = false,
  }) {
    if (reports.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay reportes para generar el código QR.')),
      );
      return;
    }

    final periodTitle = filterKey == 'semana'
        ? 'ÚLTIMA SEMANA'
        : (filterKey == 'mes'
            ? 'ÚLTIMO MES'
            : (filterKey == 'anio'
                ? 'AÑO ${DateTime.now().year}'
                : (filterKey == 'SELECCIÓN' ? 'INCIDENTES SELECCIONADOS' : 'HISTORIAL COMPLETO')));

    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (autoDownloadPdf && reports.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _printReportsDossier(
          reports,
          title: 'EXPEDIENTE POLICIAL CONSOLIDADO — $periodTitle',
          directPrint: false,
        );
      });
    }

    final String batchText = '🚨 EXPEDIENTE POLICIAL DE SEGURIDAD VECINAL\n'
        'Comunidad: Villa Escuadrón Galilea (Praderas de Coronel)\n'
        'Período: $periodTitle\n'
        'Total Incidentes: ${reports.length} verificado(s)\n'
        'Administrador: ${service.fullName.isNotEmpty ? service.fullName : "Comité de Seguridad"}\n'
        'Emisión: ${DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now())}\n\n'
        'LISTADO DE INCIDENTES:\n${reports.take(10).map((r) {
          final code = '${r['codigoReporte'] ?? r['reportCode'] ?? '#REP-${r['id']}'}';
          final tipo = '${r['tipo'] ?? 'Emergencia'}';
          final date = r['timestamp'] is num ? DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch((r['timestamp'] as num).toInt())) : '-';
          final (rLat, rLng, rAddr, _) = _resolveReportLocation(r);
          return '• $code ($tipo - $date)\n  Ubicación: $rAddr\n  GPS: ${rLat?.toStringAsFixed(5)}, ${rLng?.toStringAsFixed(5)}';
        }).join('\n\n')}\n\n'
        '📍 Navegación Satelital Base: https://www.google.com/maps/search/?api=1&query=-36.97025,-73.13600';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.qr_code_2, color: AppColors.steelBlue, size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'QR Expediente ($periodTitle)',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (autoDownloadPdf && reports.length > 1) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF10B981), width: 1.2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Descargando PDF consolidado de los ${reports.length} reportes seleccionados...',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2B3E) : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? const Color(0xFF2563EB).withValues(alpha: 0.3) : Colors.blue.shade200,
                  ),
                ),
                child: Text(
                  'Este QR contiene el acta consolidada oficial de los ${reports.length} reporte(s) de Villa Escuadrón Galilea ($periodTitle). Al escanearlo con la cámara, Carabineros o autoridades obtendrán los códigos, antecedentes, ubicaciones y plano satelital.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? const Color(0xFF93C5FD) : AppColors.brandNavy,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: QrImageView(
                  data: batchText,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _printReportsDossier(
                      reports,
                      title: 'EXPEDIENTE POLICIAL CONSOLIDADO — $periodTitle',
                      directPrint: false,
                    );
                  },
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: Text(
                    reports.length > 1
                        ? 'DESCARGAR PDF (${reports.length} REPORTES SELECCIONADOS)'
                        : 'GENERAR Y DESCARGAR EXPEDIENTE PDF',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _printReportsDossier(
                      reports,
                      title: 'EXPEDIENTE POLICIAL CONSOLIDADO — $periodTitle',
                      directPrint: true,
                    );
                  },
                  icon: const Icon(Icons.print, size: 17),
                  label: Text(
                    reports.length > 1
                        ? 'IMPRIMIR EXPEDIENTE (${reports.length} REPORTES)'
                        : 'IMPRIMIR EXPEDIENTE POLICIAL',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportNeighborsRosterPdf(List<Map<String, dynamic>> neighbors) async {
    if (neighbors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay vecinos registrados para exportar.')),
      );
      return;
    }

    try {
      final pdf = pw.Document();
      final rows = neighbors.map((n) {
        final displayName = n['nombreCompleto'] ?? n['nombre'] ?? 'Sin nombre';
        final displayAddress = n['direccionCompleta'] ??
            (n['calle'] != null
                ? '${n['calle']} #${n['casa']}'
                : (n['direccion'] != null ? '${n['direccion']} #${n['numeroCasa']}' : '-'));
        final rol = (n['rol'] == 'administrador') ? 'ADMINISTRADOR' : 'VECINO';
        final estado = (n['activo'] != false) ? 'ACTIVO' : 'DESACTIVADO';
        return [displayName, displayAddress, rol, estado];
      }).toList();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (ctx) => [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('CENTINELA URBANO - ALERTA VECINAL',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                  pw.Text('NÓMINA OFICIAL', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo700)),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text('Directorio Consolidado de Residentes y Viviendas',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text('Generado el: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())} • Total: ${neighbors.length} residentes registrados',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: ['Nombre del Residente', 'Dirección / Vivienda', 'Rol', 'Estado en Villa'],
              data: rows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.topLeft,
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            ),
          ],
        ),
      );

      final pdfBytes = await pdf.save();
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'Directorio_Vecinos_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al generar PDF de vecinos: $e')),
        );
      }
    }
  }

  Future<void> _shareTextSummary(List<Map<String, dynamic>> filtered) async {
    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay incidentes para compartir.')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('📋 *REPORTE DE INCIDENTES COMUNITARIOS*');
    buffer.writeln('Período: ${_reportFilter.toUpperCase()}');
    buffer.writeln('Total de eventos: ${filtered.length}');
    buffer.writeln('Fecha de reporte: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}\n');

    for (int i = 0; i < filtered.length; i++) {
      final r = filtered[i];
      final raw = r['timestamp'];
      String dateStr = '-';
      if (raw is num) {
        dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(raw.toInt()));
      }
      final code = '${r['codigoReporte'] ?? r['reportCode'] ?? '#REP'}';
      buffer.writeln('${i + 1}. *[$code] [${r['tipo']}]* - $dateStr');
      buffer.writeln('   👤 Vecino: ${r['emisor']}');
      if ((r['descripcion'] ?? '').toString().isNotEmpty) {
        buffer.writeln('   📝 Detalle: ${r['descripcion']}');
      }
      if ((r['ubicacion'] ?? '').toString().isNotEmpty) {
        buffer.writeln('   📍 Ubicación: ${r['ubicacion']}');
      }
      buffer.writeln('');
    }

    await SharePlus.instance.share(
      ShareParams(
        text: buffer.toString(),
        subject: 'Reporte de Alerta Vecinal',
      ),
    );
  }

  void _showCreateButtonDialog() {
    final titleCtrl = TextEditingController();
    final subtitleCtrl = TextEditingController();
    String selectedIcon = '🚨';
    String selectedColor = '#DC2626';
    bool allowsPhotos = true;
    bool requiresDescription = false;

    final icons = ['🚨', '🕵️', '🔥', '🚑', '⚠️', '🔊', '🚗', '👥', '🛑', '⚡', '🔔', '🏠', '📢', '👮'];
    final colors = [
      {'name': 'Rojo', 'hex': '#DC2626', 'color': const Color(0xFFDC2626)},
      {'name': 'Naranja', 'hex': '#EA580C', 'color': const Color(0xFFEA580C)},
      {'name': 'Ámbar', 'hex': '#D97706', 'color': const Color(0xFFD97706)},
      {'name': 'Azul', 'hex': '#2563EB', 'color': const Color(0xFF2563EB)},
      {'name': 'Púrpura', 'hex': '#7C3AED', 'color': const Color(0xFF7C3AED)},
      {'name': 'Verde', 'hex': '#0D9488', 'color': const Color(0xFF0D9488)},
      {'name': 'Gris', 'hex': '#4B5563', 'color': const Color(0xFF4B5563)},
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Crear Nuevo Botón de Alerta'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Título del Botón *',
                    hintText: 'Ej. SOSPECHOSO MERODEANDO',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: subtitleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Subtítulo / Instrucción',
                    hintText: 'Ej. Persona o auto extraño en pasaje',
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Selecciona Ícono:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: icons.map((ico) {
                    final isSel = selectedIcon == ico;
                    return InkWell(
                      onTap: () => setDlgState(() => selectedIcon = ico),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSel
                              ? (Theme.of(ctx).brightness == Brightness.dark
                                  ? const Color(0xFF2563EB).withValues(alpha: 0.3)
                                  : AppColors.brandNavy.withValues(alpha: 0.15))
                              : (Theme.of(ctx).brightness == Brightness.dark
                                  ? AppColors.darkSurface
                                  : Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSel ? AppColors.brandNavyOf(ctx) : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Text(ico, style: const TextStyle(fontSize: 22)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                const Text('Selecciona Color Identificador:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: colors.map((c) {
                    final hex = c['hex'] as String;
                    final color = c['color'] as Color;
                    final isSel = selectedColor == hex;
                    return GestureDetector(
                      onTap: () => setDlgState(() => selectedColor = hex),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: isSel ? Colors.black : Colors.white, width: isSel ? 3 : 1.5),
                          boxShadow: [
                            if (isSel)
                              const BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                          ],
                        ),
                        child: isSel ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Permite sacar fotos de evidencia', style: TextStyle(fontSize: 13)),
                  value: allowsPhotos,
                  onChanged: (v) => setDlgState(() => allowsPhotos = v ?? true),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Requiere escribir descripción y ubicación', style: TextStyle(fontSize: 13)),
                  value: requiresDescription,
                  onChanged: (v) => setDlgState(() => requiresDescription = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final t = titleCtrl.text.trim();
                if (t.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Ingresa un título para el botón.')),
                  );
                  return;
                }
                Navigator.pop(ctx);
                await service.addCustomButton(
                  title: t,
                  subtitle: subtitleCtrl.text.trim(),
                  icon: selectedIcon,
                  color: selectedColor,
                  requiresDescription: requiresDescription,
                  allowsPhotos: allowsPhotos,
                );
                setState(() {});
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nuevo botón creado y sincronizado con todos los vecinos.')),
                  );
                }
              },
              child: const Text('Crear Botón'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel Administrador'),
        actions: [
          IconButton(
            tooltip: 'Cambiar a Modo Vecino (Cerrar sesión Admin)',
            icon: const Icon(Icons.person_outline),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Row(
                    children: [
                      Icon(Icons.person_outline, color: AppColors.steelBlue),
                      SizedBox(width: 8),
                      Text('Cambiar a Modo Vecino'),
                    ],
                  ),
                  content: const Text(
                    '¿Deseas cerrar la sesión de Administrador y ver la app como Vecino con tus datos registrados?\n\nPodrás volver al Modo Administrador en cualquier momento ingresando tu huella dactilar o PIN.',
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandNavy, foregroundColor: Colors.white),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Ver como Vecino'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await service.logoutAdmin();
                if (!context.mounted) return;
                Navigator.pop(context);
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: isDark ? const Color(0xFF93C5FD) : AppColors.brandNavy,
          unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
          indicatorColor: isDark ? const Color(0xFF93C5FD) : AppColors.brandNavy,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.history), text: 'Reportes'),
            Tab(icon: Icon(Icons.people), text: 'Vecinos'),
            Tab(icon: Icon(Icons.touch_app), text: 'Botones'),
            Tab(icon: Icon(Icons.settings_suggest), text: 'Sistema'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildReportsTab(),
            _buildNeighborsTab(),
            _buildButtonsTab(),
            _buildSystemTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildReportsTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = 90.0 + MediaQuery.of(context).padding.bottom;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: service.reports(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final allReports = snapshot.data ?? [];
        final filtered = _filterReports(allReports);
        final selectedList = allReports.where((r) => _selectedReportIds.contains('${r['id']}')).toList();

        return Column(
          children: [
            // Barra de filtros y botones de descarga / impresión
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: Theme.of(context).cardColor,
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text('Filtrar:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SegmentedButton<String>(
                          showSelectedIcon: false,
                          style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          segments: const [
                            ButtonSegment(value: 'semana', label: Text('Semana', style: TextStyle(fontSize: 11))),
                            ButtonSegment(value: 'mes', label: Text('Mes', style: TextStyle(fontSize: 11))),
                            ButtonSegment(value: 'anio', label: Text('Año', style: TextStyle(fontSize: 11))),
                            ButtonSegment(value: 'todos', label: Text('Todos', style: TextStyle(fontSize: 11))),
                          ],
                          selected: {_reportFilter},
                          onSelectionChanged: (set) => setState(() => _reportFilter = set.first),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Botones de Acción Oficial
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? const Color(0xFF2563EB) : AppColors.brandNavy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: () => _exportPdfReport(filtered),
                          icon: const Icon(Icons.picture_as_pdf, size: 17),
                          label: const Text('Descargar PDF', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: () => _printReportsDossier(
                            filtered,
                            title: 'EXPEDIENTE POLICIAL — ${_reportFilter.toUpperCase()}',
                            directPrint: true,
                          ),
                          icon: const Icon(Icons.print, size: 17),
                          label: const Text('Imprimir Todo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Código QR para Autoridades (Expediente Oficial)',
                        style: IconButton.styleFrom(
                          foregroundColor: const Color(0xFF4F46E5),
                          backgroundColor: isDark ? const Color(0xFF312E81).withValues(alpha: 0.4) : const Color(0xFFEEF2FF),
                        ),
                        onPressed: () => _showBatchReportsQrDialog(filtered, _reportFilter),
                        icon: const Icon(Icons.qr_code_2, size: 22),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Compartir resumen por texto',
                        style: IconButton.styleFrom(
                          foregroundColor: AppColors.brandNavyOf(context),
                        ),
                        onPressed: () => _shareTextSummary(filtered),
                        icon: const Icon(Icons.share, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Banner de Selección Múltiple Activa (Diseño responsivo sin desbordes)
            if (_selectedReportIds.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2B3E) : const Color(0xFFE0F2FE),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? const Color(0xFF2563EB).withValues(alpha: 0.3) : const Color(0xFFBAE6FD),
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 19,
                          color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF0284C7),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_selectedReportIds.length} reporte(s) seleccionado(s)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF0369A1),
                            ),
                          ),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            foregroundColor: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                          ),
                          onPressed: () => setState(() => _selectedReportIds.clear()),
                          icon: const Icon(Icons.close, size: 15),
                          label: const Text('Limpiar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              elevation: 0.5,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () => _printReportsDossier(
                              selectedList,
                              title: 'EXPEDIENTE POLICIAL DE INCIDENTES SELECCIONADOS',
                              directPrint: true,
                            ),
                            icon: const Icon(Icons.print, size: 16),
                            label: const Text(
                              'Imprimir Selección',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              elevation: 0.5,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () => _showBatchReportsQrDialog(
                              selectedList,
                              'SELECCIÓN',
                              autoDownloadPdf: selectedList.length > 1,
                            ),
                            icon: const Icon(Icons.qr_code_2, size: 16),
                            label: Text(
                              selectedList.length > 1 ? 'QR y Descargar PDF' : 'QR Selección',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const Divider(height: 1),

            // Lista de reportes filtrados
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No hay reportes en el período seleccionado ($_reportFilter).',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async => setState(() {}),
                      child: ListView.separated(
                        padding: EdgeInsets.fromLTRB(14, 14, 14, bottomInset),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final r = filtered[index];
                          final id = '${r['id']}';
                          final reportCode = '${r['codigoReporte'] ?? r['reportCode'] ?? '#REP-$id'}';
                          final rawTime = r['timestamp'];
                          String dateStr = '';
                          if (rawTime is num) {
                            dateStr = DateFormat('dd/MM/yyyy HH:mm').format(
                              DateTime.fromMillisecondsSinceEpoch(rawTime.toInt()),
                            );
                          }
                          final fotos = r['fotosTomadas'] ?? 0;
                          final isSelected = _selectedReportIds.contains(id);

                          return Card(
                            elevation: isSelected ? 3 : 1.5,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: isSelected
                                  ? const BorderSide(color: Color(0xFF10B981), width: 1.8)
                                  : (isDark ? const BorderSide(color: AppColors.darkBorder, width: 1) : BorderSide.none),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      // Casilla de selección múltiple
                                      Checkbox(
                                        value: isSelected,
                                        activeColor: const Color(0xFF10B981),
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == true) {
                                              _selectedReportIds.add(id);
                                            } else {
                                              _selectedReportIds.remove(id);
                                            }
                                          });
                                        },
                                      ),
                                      Text(
                                        r['icono'] ?? '🚨',
                                        style: const TextStyle(fontSize: 22),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          r['tipo'] ?? 'Emergencia',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                      ),
                                      // Botones de acción compactos
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            padding: const EdgeInsets.all(5),
                                            constraints: const BoxConstraints(),
                                            tooltip: 'Generar y Compartir PDF',
                                            icon: const Icon(Icons.picture_as_pdf, color: Colors.deepOrange, size: 20),
                                            onPressed: () => _printReportsDossier(
                                              [r],
                                              title: 'FICHA INDIVIDUAL DE INCIDENTE - $reportCode',
                                              directPrint: false,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            padding: const EdgeInsets.all(5),
                                            constraints: const BoxConstraints(),
                                            tooltip: _selectedReportIds.length > 1 && _selectedReportIds.contains(id)
                                                ? 'Ver QR y Descargar PDF (${_selectedReportIds.length} seleccionados)'
                                                : 'Ver QR para Autoridades',
                                            icon: const Icon(Icons.qr_code_2, color: AppColors.steelBlue, size: 21),
                                            onPressed: () {
                                              if (_selectedReportIds.length > 1 && _selectedReportIds.contains(id)) {
                                                _showBatchReportsQrDialog(
                                                  selectedList,
                                                  'SELECCIÓN',
                                                  autoDownloadPdf: true,
                                                );
                                              } else {
                                                _showReportQrDialog(r);
                                              }
                                            },
                                          ),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            padding: const EdgeInsets.all(5),
                                            constraints: const BoxConstraints(),
                                            tooltip: 'Imprimir esta Ficha Policial',
                                            icon: const Icon(Icons.print, color: Color(0xFF10B981), size: 19),
                                            onPressed: () => _printReportsDossier(
                                              [r],
                                              title: 'FICHA INDIVIDUAL DE INCIDENTE - $reportCode',
                                              directPrint: true,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            padding: const EdgeInsets.all(5),
                                            constraints: const BoxConstraints(),
                                            tooltip: 'Eliminar este reporte',
                                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 19),
                                            onPressed: () async {
                                              final ok = await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  title: const Text('Eliminar reporte'),
                                                  content: const Text('¿Deseas eliminar este registro de incidente?'),
                                                  actions: [
                                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                                    ElevatedButton(
                                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                                      onPressed: () => Navigator.pop(ctx, true),
                                                      child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (ok == true) {
                                                await service.deleteReport(id);
                                                setState(() {
                                                  _selectedReportIds.remove(id);
                                                });
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.steelBlue.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          reportCode,
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.steelBlue),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Emisor: ${r['emisor'] ?? 'Desconocido'}',
                                          style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if ((r['descripcion'] ?? '').toString().isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text('Detalle: ${r['descripcion']}', style: const TextStyle(fontSize: 13)),
                                  ],
                                  if ((r['ubicacion'] ?? '').toString().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.location_on, size: 14, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '${r['ubicacion']}',
                                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      if (fotos is num && fotos > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '📷 $fotos fotos de respaldo',
                                            style: TextStyle(fontSize: 11, color: Colors.blue.shade900, fontWeight: FontWeight.bold),
                                          ),
                                        )
                                      else
                                        const SizedBox.shrink(),
                                      Text(dateStr, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _buildReportLocalPhotosSection(id, reportCode, isDark),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildReportLocalPhotosSection(String reportId, String reportCode, bool isDark) {
    return FutureBuilder<List<String>>(
      future: _getReportPhotos(reportId, reportCode: reportCode),
      builder: (context, snapshot) {
        final photos = snapshot.data ?? [];
        if (photos.isEmpty) {
          return Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showAttachPhotoSheet(reportId, reportCode),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_a_photo, size: 14, color: isDark ? const Color(0xFF93C5FD) : AppColors.steelBlue),
                    const SizedBox(width: 6),
                    Text(
                      'Adjuntar foto al reporte (para PDF policial)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFF93C5FD) : AppColors.brandNavy,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.photo_library, size: 14, color: Color(0xFF10B981)),
                  const SizedBox(width: 6),
                  Text(
                    '${photos.length} foto(s) adjunta(s) en PDF',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _showAttachPhotoSheet(reportId, reportCode),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        children: [
                          Icon(Icons.add, size: 13, color: isDark ? const Color(0xFF93C5FD) : AppColors.steelBlue),
                          const SizedBox(width: 2),
                          Text(
                            'Añadir',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFF93C5FD) : AppColors.steelBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 70,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final photoPath = photos[idx];
                    final file = File(photoPath);
                    return Stack(
                      children: [
                        GestureDetector(
                          onTap: () => _viewFullPhoto(photoPath, reportCode),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 70,
                              height: 70,
                              color: Colors.black12,
                              child: file.existsSync()
                                  ? Image.file(file, fit: BoxFit.cover)
                                  : const Center(child: Icon(Icons.broken_image, size: 22, color: Colors.grey)),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => _removeReportPhoto(reportId, photoPath),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 11, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAdminEditNeighborDialog(Map<String, dynamic> neighbor) {
    final id = '${neighbor['id']}';
    final currentFirst = '${neighbor['nombre'] ?? ''}'.trim();
    final currentL1 = '${neighbor['apellido1'] ?? ''}'.trim();
    final currentL2 = '${neighbor['apellido2'] ?? ''}'.trim();
    final currentAddr = '${neighbor['direccion'] ?? neighbor['calle'] ?? ''}'.trim();
    final currentNum = '${neighbor['numeroCasa'] ?? neighbor['casa'] ?? ''}'.trim();
    final currentAttempts = (neighbor['intentosEdicion'] as num?)?.toInt() ?? 0;

    final firstCtrl = TextEditingController(text: currentFirst);
    final l1Ctrl = TextEditingController(text: currentL1);
    final l2Ctrl = TextEditingController(text: currentL2);
    final addrCtrl = TextEditingController(text: currentAddr);
    final houseCtrl = TextEditingController(text: currentNum);

    bool resetAttempts = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.edit, color: isDark ? const Color(0xFF93C5FD) : AppColors.brandNavy),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Editar Vecino: ${neighbor['nombreCompleto'] ?? neighbor['nombre'] ?? id}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Como Administrador puedes corregir faltas de ortografía, nombres mal ingresados o calles/números incorrectos.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(dialogCtx)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: firstCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre(s) *',
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: l1Ctrl,
                    decoration: const InputDecoration(
                      labelText: 'Primer Apellido *',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: l2Ctrl,
                    decoration: const InputDecoration(
                      labelText: 'Segundo Apellido *',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: addrCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Calle / Pasaje *',
                      prefixIcon: Icon(Icons.add_road),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: houseCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Número de Casa *',
                      prefixIcon: Icon(Icons.home),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Intentos de autocorrección: $currentAttempts / 3',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: currentAttempts >= 3 ? Colors.red : AppColors.textPrimaryOf(dialogCtx),
                              ),
                            ),
                            if (currentAttempts > 0)
                              Switch(
                                value: resetAttempts,
                                onChanged: (val) => setDialogState(() => resetAttempts = val),
                              ),
                          ],
                        ),
                        if (currentAttempts >= 3)
                          const Text(
                            '⚠️ Este vecino agotó sus 3 intentos y tiene el perfil bloqueado para autocorrección. Activa el interruptor arriba para restablecer sus 3 intentos a cero.',
                            style: TextStyle(fontSize: 11, color: Colors.red),
                          )
                        else if (currentAttempts > 0)
                          Text(
                            resetAttempts
                                ? '✓ Se restablecerán los intentos a 0 al guardar.'
                                : 'Puedes restablecer sus intentos para permitirle editar nuevamente.',
                            style: TextStyle(
                              fontSize: 11,
                              color: resetAttempts ? Colors.green : AppColors.textSecondaryOf(dialogCtx),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final fName = firstCtrl.text.trim();
                  final l1 = l1Ctrl.text.trim();
                  final l2 = l2Ctrl.text.trim();
                  final addr = addrCtrl.text.trim();
                  final numC = houseCtrl.text.trim();

                  if (fName.isEmpty || l1.isEmpty || l2.isEmpty || addr.isEmpty || numC.isEmpty) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(
                      const SnackBar(content: Text('Por favor completa todos los campos.')),
                    );
                    return;
                  }

                  final errFn = NeighborhoodLocations.validateHumanName(fName, 'Nombre');
                  if (errFn != null) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(SnackBar(content: Text(errFn)));
                    return;
                  }

                  final errL1 = NeighborhoodLocations.validateHumanName(l1, 'Primer apellido');
                  if (errL1 != null) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(SnackBar(content: Text(errL1)));
                    return;
                  }

                  final errL2 = NeighborhoodLocations.validateHumanName(l2, 'Segundo apellido');
                  if (errL2 != null) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(SnackBar(content: Text(errL2)));
                    return;
                  }

                  final numRegExp = RegExp(r'[0-9]');
                  if (!numRegExp.hasMatch(numC)) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(
                      const SnackBar(content: Text('El número de casa debe contener dígitos numéricos.')),
                    );
                    return;
                  }

                  await service.adminUpdateNeighbor(
                    id,
                    firstName: fName,
                    lastName1: l1,
                    lastName2: l2,
                    address: addr,
                    houseNumber: numC,
                  );

                  if (resetAttempts) {
                    await service.adminResetNeighborAttempts(id);
                  }

                  if (!dialogCtx.mounted) return;
                  Navigator.pop(dialogCtx);
                  if (!mounted) return;
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.sageGreen,
                      content: Text('Datos del vecino $fName actualizados correctamente en la red.'),
                    ),
                  );
                },
                child: const Text('Guardar Cambios'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _incrementVersion(String current) {
    try {
      final parts = current.trim().split('.');
      if (parts.length == 3) {
        final patch = int.tryParse(parts[2]) ?? 0;
        return '${parts[0]}.${parts[1]}.${patch + 1}';
      } else if (parts.isNotEmpty) {
        final last = int.tryParse(parts.last) ?? 0;
        parts[parts.length - 1] = '${last + 1}';
        return parts.join('.');
      }
    } catch (_) {}
    return '1.0.4';
  }

  String _getDefaultImprovementNotes() {
    return '• Soporte hasta 3 teléfonos por vivienda y cupos adicionales (\$5.000)\n'
        '• Descarga directa de expedientes policiales en PDF\n'
        '• Sirena a máximo volumen y manuales de usuario HD';
  }

  void _appendNote(String note) {
    setState(() {
      final current = _updateNotesCtrl.text.trim();
      if (current.isEmpty) {
        _updateNotesCtrl.text = '• $note';
      } else if (!current.contains(note)) {
        _updateNotesCtrl.text = '$current\n• $note';
      }
    });
  }

  Future<void> _showHouseDeviceManagementDialog(Map<String, dynamic> neighbor) async {
    final addr = (neighbor['direccion'] ?? neighbor['calle'] ?? '').toString().trim();
    final house = (neighbor['numeroCasa'] ?? neighbor['casa'] ?? '').toString().trim();
    if (addr.isEmpty || house.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta vivienda no tiene dirección o número válido.')),
      );
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return FutureBuilder<List<dynamic>>(
            future: Future.wait([
              service.getNeighborsInHouse(addr, house),
              service.getHouseDeviceLimit(addr, house),
            ]),
            builder: (ctx, snapshot) {
              if (!snapshot.hasData) {
                return const AlertDialog(
                  content: SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }

              final inHouse = snapshot.data![0] as List<Map<String, dynamic>>;
              final limit = snapshot.data![1] as int;
              final extraPaid = limit > 3 ? (limit - 3) : 0;

              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    const Icon(Icons.phone_android, color: Color(0xFF0D9488), size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cupos: $addr #$house',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
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
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF134E4A) : const Color(0xFFCCFBF1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF14B8A6)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Dispositivos Autorizados:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : const Color(0xFF115E59),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D9488),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${inHouse.length} de $limit cupos',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              extraPaid > 0
                                  ? '✓ Plan Base: 3 teléfonos + $extraPaid cupo(s) extra pagado(s) (\$5.000 c/u).'
                                  : '• Plan Base estándar: 3 teléfonos incluidos en el paquete comunitario.',
                              style: TextStyle(fontSize: 11.5, color: isDark ? const Color(0xFF99F6E4) : const Color(0xFF0F766E)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Familiares / Teléfonos Registrados (${inHouse.length}):',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      if (inHouse.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text('No hay residentes registrados aún en esta casa.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        )
                      else
                        ...inHouse.map((m) {
                          final name = m['nombreCompleto'] ?? m['nombre'] ?? 'Vecino';
                          final tel = m['telefono'] ?? 'Sin teléfono';
                          final act = m['activo'] != false;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.person, size: 16, color: act ? Colors.green : Colors.red),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                      Text('📱 $tel', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: act ? Colors.green.shade50 : Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    act ? 'Activo' : 'Inactivo',
                                    style: TextStyle(color: act ? Colors.green.shade800 : Colors.red.shade800, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      // Botón para habilitar 1 nuevo teléfono
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D9488),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () async {
                            final newLimit = limit + 1;
                            await service.setHouseDeviceLimit(
                              addr,
                              house,
                              newLimit,
                              extraPaidCount: (newLimit - 3),
                            );
                            setDlgState(() {});
                            if (mounted) {
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: const Color(0xFF0D9488),
                                  content: Text('✓ ¡Cupo ampliado! Ahora $addr #$house puede registrar hasta $newLimit teléfonos.'),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          label: const Text(
                            '+ HABILITAR 1 TELÉFONO ADICIONAL (\$5.000 PAGADOS)',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      if (limit > 3) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: Colors.grey),
                            onPressed: () async {
                              final newLimit = limit - 1;
                              await service.setHouseDeviceLimit(
                                addr,
                                house,
                                newLimit,
                                extraPaidCount: (newLimit > 3 ? (newLimit - 3) : 0),
                              );
                              setDlgState(() {});
                              if (mounted) setState(() {});
                            },
                            icon: const Icon(Icons.remove_circle_outline, size: 14),
                            label: const Text('Reducir 1 cupo', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cerrar'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showAllHousesManagementDialog(List<Map<String, dynamic>> allNeighbors) async {
    final Map<String, List<Map<String, dynamic>>> houseGroups = {};
    for (final n in allNeighbors) {
      final addr = (n['direccion'] ?? n['calle'] ?? 'Sin Calle').toString().trim();
      final house = (n['numeroCasa'] ?? n['casa'] ?? '0').toString().trim();
      final key = '$addr #$house';
      houseGroups.putIfAbsent(key, () => []).add(n);
    }

    final sortedKeys = houseGroups.keys.toList()..sort();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.family_restroom, color: AppColors.steelBlue, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Gestión de Cupos por Vivienda',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lista de todas las viviendas con sus teléfonos vinculados. Toca cualquier vivienda para sumar cupos adicionales tras recibir el pago de \$5.000.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(ctx)),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sortedKeys.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final houseKey = sortedKeys[i];
                    final members = houseGroups[houseKey]!;
                    final first = members.first;

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.home, color: members.length >= 3 ? Colors.teal : AppColors.brandNavy),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '🏠 $houseKey',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${members.length} teléfono(s): ${members.map((m) => m['nombre'] ?? m['nombreCompleto'] ?? '').take(3).join(', ')}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0D9488),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showHouseDeviceManagementDialog(first);
                            },
                            icon: const Icon(Icons.settings, size: 14),
                            label: const Text('Gestionar Cupos', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showPlanStatusDialog(Map<String, dynamic> neighbor) {
    final id = '${neighbor['id']}';
    final name = neighbor['nombreCompleto'] ?? neighbor['nombre'] ?? 'Vecino';
    final address = neighbor['direccionCompleta'] ??
        (neighbor['calle'] != null
            ? '${neighbor['calle']} #${neighbor['casa']}'
            : (neighbor['direccion'] != null ? '${neighbor['direccion']} #${neighbor['numeroCasa']}' : '-'));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final trial = service.getTrialStatus(neighbor);
          final isTrial = trial['isTrial'] == true;
          final isExpired = trial['isExpired'] == true;
          final isPermanent = trial['isPermanent'] == true;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(
                  isPermanent ? Icons.verified : (isExpired ? Icons.timer_off : Icons.hourglass_top),
                  color: isPermanent ? Colors.teal : (isExpired ? Colors.red : Colors.amber.shade800),
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Gestión de Plan y Prueba',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '🏠 $address',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(ctx)),
                  ),
                  const Divider(height: 20),

                  // Estado actual del plan
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isExpired
                          ? Colors.red.shade50
                          : (isTrial
                              ? (isDark ? const Color(0xFF33230A) : Colors.amber.shade50)
                              : (isDark ? const Color(0xFF064E3B) : Colors.teal.shade50)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isExpired
                            ? Colors.red.shade300
                            : (isTrial ? Colors.amber.shade400 : Colors.teal.shade300),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              isPermanent ? 'PLAN DEFINITIVO' : (isExpired ? 'PRUEBA FINALIZADA' : 'MES DE PRUEBA ACTIVO'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isExpired
                                    ? Colors.red.shade900
                                    : (isTrial ? Colors.amber.shade900 : Colors.teal.shade900),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (isTrial) ...[
                          Text(
                            isExpired
                                ? 'El período de prueba de 1 mes ha vencido.'
                                : 'Tiempo restante del mes de prueba:',
                            style: TextStyle(fontSize: 12, color: AppColors.textPrimaryOf(ctx)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isExpired
                                ? '⚠️ El vecino no podrá sonar la alarma comunitaria hasta adquirir el plan o extender la prueba.'
                                : '⏳ ${trial['daysLeft']} días, ${trial['hoursLeft']} horas, ${trial['minutesLeft']} minutos, ${trial['secondsLeft']} segundos',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isExpired ? Colors.red.shade800 : (isDark ? Colors.amber.shade300 : Colors.amber.shade900),
                            ),
                          ),
                        ] else ...[
                          Text(
                            '✓ Cuenta con Plan Definitivo (Uso Normal Adquirido)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFF6EE7B7) : Colors.teal.shade800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Este vecino tiene acceso normal sin límite de tiempo.',
                            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondaryOf(ctx)),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Text(
                    'Acciones de Administrador:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  // Botón 1: Dejar listo para uso normal / Plan Definitivo
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        await service.setNeighborPlan(id, 'definitivo');
                        neighbor['tipoPlan'] = 'definitivo';
                        if (!dialogCtx.mounted) return;
                        Navigator.pop(dialogCtx);
                        if (!mounted) return;
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF059669),
                            content: Text('✓ Vecino $name activado con Plan Definitivo (Uso Normal Adquirido).'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text(
                        'Activar Plan Definitivo (Uso Normal)',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Botón 2: Extender 1 mes más de prueba (+30 días)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.steelBlue,
                        side: const BorderSide(color: AppColors.steelBlue),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        await service.extendNeighborTrial(id, days: 30);
                        neighbor['tipoPlan'] = 'prueba';
                        neighbor['finPrueba'] = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch;
                        if (!dialogCtx.mounted) return;
                        Navigator.pop(dialogCtx);
                        if (!mounted) return;
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.steelBlue,
                            content: Text('⏳ Se han otorgado 30 días adicionales de prueba a $name.'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.more_time, size: 18),
                      label: const Text(
                        'Extender Prueba (+30 Días)',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ),

                  if (!isExpired && isTrial) ...[
                    const SizedBox(height: 8),
                    // Botón 3: Vencer prueba ahora
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red.shade800,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: dialogCtx,
                            builder: (c) => AlertDialog(
                              title: const Text('Finalizar Prueba'),
                              content: Text('¿Deseas finalizar de inmediato el mes de prueba de $name?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text('Finalizar Prueba', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await service.expireNeighborTrial(id);
                            neighbor['tipoPlan'] = 'prueba';
                            neighbor['finPrueba'] = DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch;
                            if (!dialogCtx.mounted) return;
                            Navigator.pop(dialogCtx);
                            if (!mounted) return;
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: Colors.red.shade800,
                                content: Text('Prueba de $name finalizada.'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.timer_off_outlined, size: 16),
                        label: const Text('Finalizar Mes de Prueba Ahora', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNeighborsTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = 90.0 + MediaQuery.of(context).padding.bottom;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: service.getNeighbors(),
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final neighbors = snapshot.data ?? [];
        if (neighbors.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.people_outline, size: 64, color: AppColors.textMuted),
                  const SizedBox(height: 16),
                  const Text(
                    'No hay vecinos registrados aún en Firebase.',
                    style: TextStyle(fontSize: 16, color: AppColors.textMuted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Refrescar'),
                  ),
                ],
              ),
            ),
          );
        }
        final total = neighbors.length;
        final activos = neighbors.where((n) => n['activo'] != false).length;
        final inactivos = total - activos;

        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset),
            itemCount: neighbors.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, index) {
              if (index == 0) {
                return Card(
                  elevation: 1.5,
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Padrón Comunitario de Vecinos',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimaryOf(context),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Total: $total  •  Activos: $activos  •  Desactivados: $inactivos',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF3B82F6) : AppColors.steelBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              ),
                              onPressed: () => _exportNeighborsRosterPdf(neighbors),
                              icon: const Icon(Icons.picture_as_pdf, size: 15),
                              label: const Text('Nómina PDF', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(height: 6),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E),
                                backgroundColor: isDark ? const Color(0xFF134E4A).withOpacity(0.4) : const Color(0xFFCCFBF1).withOpacity(0.7),
                                side: BorderSide(color: isDark ? const Color(0xFF14B8A6) : const Color(0xFF0D9488), width: 1.5),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => _showAllHousesManagementDialog(neighbors),
                              icon: const Icon(Icons.family_restroom, size: 18),
                              label: const Text('Cupos por Casa', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }

              final n = neighbors[index - 1];
              final id = '${n['id']}';
              final isAdminNeighbor = n['rol'] == 'administrador';
              final isActivo = n['activo'] != false;
              final displayName = n['nombreCompleto'] ?? n['nombre'] ?? 'Sin nombre';
              final displayAddress = n['direccionCompleta'] ??
                  (n['calle'] != null
                      ? '${n['calle']} #${n['casa']}'
                      : (n['direccion'] != null ? '${n['direccion']} #${n['numeroCasa']}' : '-'));
              final trial = service.getTrialStatus(n);

              // Detección de posibles duplicados
              final isPotentialDup = neighbors.any((other) => other['id'] != id && AlarmSyncService.isPotentialDuplicate(n, other));

              return Card(
                elevation: 1.5,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: isAdminNeighbor
                                ? (isDark ? const Color(0xFF2563EB).withValues(alpha: 0.25) : AppColors.brandNavy.withValues(alpha: 0.15))
                                : (isActivo ? AppColors.sageGreen.withValues(alpha: 0.2) : (isDark ? Colors.red.shade900.withValues(alpha: 0.3) : Colors.red.shade100)),
                            child: Icon(
                              isAdminNeighbor ? Icons.shield : Icons.home,
                              color: isAdminNeighbor ? (isDark ? const Color(0xFF93C5FD) : AppColors.brandNavy) : (isActivo ? AppColors.sageGreen : Colors.red),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        displayName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: AppColors.textPrimaryOf(context),
                                        ),
                                      ),
                                    ),
                                    if (isAdminNeighbor)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF2563EB) : AppColors.brandNavy,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text('ADMIN',
                                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '🏠 $displayAddress',
                                  style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isActivo ? Colors.green : Colors.red,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isActivo ? 'VECINO ACTIVO' : 'DESACTIVADO (Fuera de la villa)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isActivo ? Colors.green.shade800 : Colors.red.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: trial['isExpired'] == true
                                            ? Colors.red.shade100
                                            : (trial['isTrial'] == true
                                                ? (isDark ? const Color(0xFF3B2D04) : Colors.amber.shade100)
                                                : (isDark ? const Color(0xFF064E3B) : Colors.teal.shade50)),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: trial['isExpired'] == true
                                              ? Colors.red.shade400
                                              : (trial['isTrial'] == true
                                                  ? Colors.amber.shade700
                                                  : Colors.teal.shade300),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            trial['isExpired'] == true
                                                ? Icons.timer_off
                                                : (trial['isTrial'] == true ? Icons.hourglass_top : Icons.verified),
                                            size: 12,
                                            color: trial['isExpired'] == true
                                                ? Colors.red.shade900
                                                : (trial['isTrial'] == true ? Colors.amber.shade900 : Colors.teal.shade900),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            trial['isTrial'] == true
                                                ? (trial['isExpired'] == true
                                                    ? 'Prueba Vencida (1 Mes cumplido)'
                                                    : 'Prueba: ${trial['daysLeft']}d ${trial['hoursLeft']}h restantes')
                                                : '${trial['label']}',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: trial['isExpired'] == true
                                                  ? Colors.red.shade900
                                                  : (trial['isTrial'] == true ? Colors.amber.shade900 : Colors.teal.shade900),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (isPotentialDup) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.amber.shade800),
                                    ),
                                    child: Text(
                                      '⚠️ Posible Cuenta Duplicada',
                                      style: TextStyle(color: Colors.amber.shade900, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                                Builder(
                                  builder: (_) {
                                    final intentos = (n['intentosEdicion'] as num?)?.toInt() ?? 0;
                                    if (intentos <= 0) return const SizedBox.shrink();
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(
                                        children: [
                                          Icon(
                                            intentos >= 3 ? Icons.lock : Icons.edit_note,
                                            size: 13,
                                            color: intentos >= 3 ? Colors.red : Colors.grey.shade600,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            intentos >= 3
                                                ? 'Bloqueado: Agotó 3/3 correcciones permitidas'
                                                : 'Intentos de autocorrección: $intentos / 3',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: intentos >= 3 ? FontWeight.bold : FontWeight.normal,
                                              color: intentos >= 3 ? Colors.red : AppColors.textSecondaryOf(context),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // BOTONES DE ADMINISTRACIÓN DE VECINO
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Botón Editar Datos para Administrador
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.steelBlue,
                              side: const BorderSide(color: AppColors.steelBlue),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            onPressed: () => _showAdminEditNeighborDialog(n),
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('Editar Datos', style: TextStyle(fontSize: 12)),
                          ),

                          // Botón 4: Plan / Mes de Prueba (Días restantes)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: trial['isExpired'] == true
                                  ? Colors.red
                                  : (trial['isTrial'] == true ? Colors.amber.shade900 : Colors.teal.shade800),
                              side: BorderSide(
                                color: trial['isExpired'] == true
                                    ? Colors.red
                                    : (trial['isTrial'] == true ? Colors.amber.shade700 : Colors.teal),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            onPressed: () => _showPlanStatusDialog(n),
                            icon: Icon(
                              trial['isTrial'] == true ? Icons.hourglass_top : Icons.verified_user,
                              size: 16,
                            ),
                            label: Text(
                              trial['isTrial'] == true
                                  ? (trial['isExpired'] == true ? 'Prueba Vencida' : 'Plan / Prueba (${trial['daysLeft']}d)')
                                  : 'Plan / Vigencia',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),

                          // Botón Cupos Casa (+1 teléfono por $5.000)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark ? const Color(0xFF134E4A) : const Color(0xFFCCFBF1),
                              foregroundColor: isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E),
                              elevation: 0,
                              side: BorderSide(color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488), width: 1.5),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () => _showHouseDeviceManagementDialog(n),
                            icon: const Icon(Icons.phone_android, size: 18),
                            label: const Text('Cupos Casa (\$5.000)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          ),

                          if (!isAdminNeighbor && id != service.neighborId) ...[
                            // Botón 1: Desactivar / Activar
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isActivo ? Colors.orange.shade800 : Colors.green.shade800,
                                side: BorderSide(color: isActivo ? Colors.orange : Colors.green),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              onPressed: () async {
                                await service.toggleNeighborStatus(id, !isActivo);
                                if (!mounted) return;
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(isActivo
                                        ? 'Vecino $displayName desactivado de la red.'
                                        : 'Vecino $displayName reactivado en la red.'),
                                  ),
                                );
                              },
                              icon: Icon(isActivo ? Icons.pause_circle_outline : Icons.play_circle_outline, size: 16),
                              label: Text(isActivo ? 'Desactivar' : 'Reactivar', style: const TextStyle(fontSize: 12)),
                            ),

                            // Botón 2: Eliminar
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Eliminar vecino'),
                                    content: Text('¿Deseas eliminar permanentemente a "$displayName" del sistema?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await service.deleteNeighbor(id);
                                  setState(() {});
                                }
                              },
                              icon: const Icon(Icons.delete_forever, size: 16),
                              label: const Text('Eliminar', style: TextStyle(fontSize: 12)),
                            ),
                          ] else ...[
                            // Cuenta Administrador protegida contra auto-desactivación o eliminación
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF3B82F6) : AppColors.brandNavy.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.verified_user, size: 14, color: isDark ? const Color(0xFF93C5FD) : AppColors.brandNavy),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Cuenta Administrador (Protegida)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? const Color(0xFF93C5FD) : AppColors.brandNavy,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildButtonsTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = 90.0 + MediaQuery.of(context).padding.bottom;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF2563EB) : AppColors.brandNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _showCreateButtonDialog,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Crear Nuevo Botón de Alerta', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<EmergencyButton>>(
            stream: service.buttonsStream,
            initialData: service.buttons.isEmpty ? AlarmSyncService.defaults : service.buttons,
            builder: (context, snapshot) {
              final list = snapshot.data ?? AlarmSyncService.defaults;
              return ListView.separated(
                padding: EdgeInsets.fromLTRB(14, 14, 14, bottomInset),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final b = list[index];
                  final isDefault = b.id == '1' || b.id == '2' || b.id == '3';

                  Color cardBorderColor;
                  try {
                    cardBorderColor = Color(int.parse('FF${b.color.replaceAll('#', '')}', radix: 16));
                  } catch (_) {
                    cardBorderColor = Colors.grey;
                  }

                  return Card(
                    elevation: 1.5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: cardBorderColor, width: 1.5),
                    ),
                    child: ListTile(
                      leading: Text(b.icon, style: const TextStyle(fontSize: 30)),
                      title: Text(b.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (b.subtitle.isNotEmpty) Text(b.subtitle, style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: b.allowsPhotos ? Colors.green.shade50 : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  b.allowsPhotos ? '📷 Permite fotos' : '🚫 Sin fotos',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: b.allowsPhotos ? Colors.green.shade800 : Colors.grey.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: b.requiresDescription ? Colors.blue.shade50 : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  b.requiresDescription ? '📝 Requiere descripción' : '⚡ Alerta directa',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: b.requiresDescription ? Colors.blue.shade800 : Colors.grey.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      trailing: isDefault
                          ? const Chip(label: Text('Fijo', style: TextStyle(fontSize: 10)))
                          : IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              tooltip: 'Eliminar botón personalizado',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Eliminar botón'),
                                    content: Text('¿Deseas eliminar el botón "${b.title}" para todos los vecinos?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await service.deleteCustomButton(b.id);
                                  setState(() {});
                                }
                              },
                            ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSystemTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = 90.0 + MediaQuery.of(context).padding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset),
      children: [
        // 0.A Vista Previa del Registro de Vecinos (Popup para Administrador)
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: isDark ? const Color(0xFF3B82F6).withValues(alpha: 0.5) : const Color(0xFF93C5FD), width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E3A8A) : Colors.blue.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.preview_outlined, color: Color(0xFF2563EB), size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vista Previa del Registro de Vecinos',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimaryOf(context)),
                          ),
                          Text(
                            'Explora exactamente cómo se ve la inscripción',
                            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondaryOf(context)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Abre una ventana emergente (popup) con la pantalla completa de registro tal como la ven los vecinos: selectores jerárquicos (Región del Biobío, Coronel, Villa Galilea, pasajes reales, números de casa 2400 a 2520), validación anti-datos falsos y la pestaña de restauración con PIN.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context), height: 1.35),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => Dialog(
                          insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          clipBehavior: Clip.antiAlias,
                          child: SizedBox(
                            width: double.infinity,
                            height: MediaQuery.of(ctx).size.height * 0.92,
                            child: const RegisterScreen(isPreview: true),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text(
                      'VER CÓMO SE VE EL REGISTRO (POPUP)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 0.B Alternar entre Modo Administrador y Modo Vecino
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: isDark ? const Color(0xFF059669).withValues(alpha: 0.5) : const Color(0xFFA7F3D0), width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF064E3B) : Colors.green.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.switch_account_outlined, color: Color(0xFF059669), size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alternar Modo Vecino / Administrador',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimaryOf(context)),
                          ),
                          Text(
                            'Usa la app con tus datos de residente',
                            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondaryOf(context)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Como administrador estás registrado con tu propio nombre y domicilio de Villa Galilea. Puedes cambiar a "Modo Vecino" para ver y experimentar la app exactamente como cualquier residente. Para volver al Modo Administrador, simplemente toca el escudo en la barra superior o en Ajustes e ingresa con tu huella o PIN.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context), height: 1.35),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF059669),
                      side: const BorderSide(color: Color(0xFF059669), width: 1.6),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Row(
                            children: [
                              Icon(Icons.person_outline, color: Color(0xFF059669)),
                              SizedBox(width: 8),
                              Text('Cambiar a Modo Vecino'),
                            ],
                          ),
                          content: const Text(
                            'La sesión de Administrador se cerrará para que puedas ver y usar la aplicación como vecino normal con tus datos registrados.\n\nPara volver al Administrador, bastará con autenticarte con tu huella dactilar o PIN.',
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF059669),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Confirmar y Ver como Vecino'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await service.logoutAdmin();
                        if (!mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: AppColors.brandNavy,
                            content: Text('Ahora estás en Modo Vecino con tus datos registrados.'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.person, size: 18),
                    label: const Text(
                      'VER COMO VECINO (CERRAR SESIÓN ADMIN)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 1. Comunicado Oficial Comunitario (Aviso Silencioso sin sirena)
        Card(
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.campaign, color: Color(0xFF6366F1), size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Publicar Comunicado Oficial',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimaryOf(context)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Difunde avisos comunitarios (reuniones, cortes de servicios, rondines). Aparecerán destacados en la pantalla de todos los vecinos sin activar la sirena sonora.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _comunicadoTituloCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Título del Comunicado',
                    hintText: 'Ej. Corte de agua programado',
                    prefixIcon: Icon(Icons.title),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _comunicadoMensajeCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Mensaje o Detalle',
                    hintText: 'Ej. Este jueves de 15:00 a 18:00 hrs por mantención en la matriz.',
                    prefixIcon: Icon(Icons.notes),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () async {
                          final tit = _comunicadoTituloCtrl.text.trim();
                          final msg = _comunicadoMensajeCtrl.text.trim();
                          if (tit.isNotEmpty && msg.isNotEmpty) {
                            await service.publishCommunityNotice(title: tit, message: msg);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Comunicado oficial publicado a todos los vecinos.')),
                              );
                            }
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Ingresa título y mensaje para publicar.')),
                            );
                          }
                        },
                        icon: const Icon(Icons.send, size: 16),
                        label: const Text('Publicar Aviso'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () async {
                        await service.deleteCommunityNotice();
                        setState(() {
                          _comunicadoTituloCtrl.clear();
                          _comunicadoMensajeCtrl.clear();
                        });
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Comunicado activo retirado.')),
                          );
                        }
                      },
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Retirar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 2. Teléfono de Seguridad Ciudadana / Plan Cuadrante
        Card(
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.local_police, color: AppColors.steelBlue, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Teléfono Seguridad Ciudadana / Cuadrante',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimaryOf(context)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Configura el número de la patrulla o cuadrante. Se sincronizará en el botón de marcación rápida de 1-toque en los teléfonos de todos los vecinos.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _seguridadPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: '1414 o +569XXXXXXXX',
                          prefixIcon: Icon(Icons.phone_forwarded, color: AppColors.steelBlue),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.steelBlue,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        final phone = _seguridadPhoneCtrl.text.trim();
                        if (phone.isNotEmpty) {
                          await service.setSeguridadCiudadanaPhone(phone);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Teléfono de seguridad guardado: $phone')),
                            );
                          }
                        }
                      },
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 3. WhatsApp del Administrador para Evidencias
        Card(
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.phone_android, color: Color(0xFF25D366)),
                    SizedBox(width: 8),
                    Text('WhatsApp del Administrador', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Número donde los vecinos enviarán las fotografías de evidencia junto con el código del reporte (#REP-XXXX) autogenerado.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _whatsappCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: '+56912345678',
                          prefixIcon: Icon(Icons.chat, color: Color(0xFF25D366)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
                      onPressed: () async {
                        final phone = _whatsappCtrl.text.trim();
                        if (phone.isNotEmpty) {
                          await service.setAdminWhatsApp(phone);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('WhatsApp de administración actualizado: $phone')),
                            );
                          }
                        }
                      },
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 2. Generador de Código QR de Descarga de APK
        Card(
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.system_update_alt, color: AppColors.brandNavyOf(context)),
                    const SizedBox(width: 8),
                    const Text('Actualizaciones de la App (OTA)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Publica una nueva versión para que a todos los vecinos les aparezca un botón directo de actualización en su pantalla, sin tener que escanear códigos QR uno por uno.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _qrUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Enlace de Descarga del APK (Directo, Drive o GitHub)',
                    hintText: 'https://...',
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _updateVersionCtrl,
                        decoration: InputDecoration(
                          labelText: 'Versión (ej: 1.0.4)',
                          prefixIcon: const Icon(Icons.tag),
                          suffixIcon: IconButton(
                            tooltip: 'Auto-incrementar versión',
                            icon: const Icon(Icons.exposure_plus_1, size: 20),
                            onPressed: () {
                              setState(() {
                                _updateVersionCtrl.text = _incrementVersion(_updateVersionCtrl.text);
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: _updateNotesCtrl,
                        maxLines: 2,
                        minLines: 1,
                        decoration: InputDecoration(
                          labelText: 'Novedades / Mejoras',
                          prefixIcon: const Icon(Icons.article_outlined),
                          suffixIcon: IconButton(
                            tooltip: 'Cargar novedades automáticas',
                            icon: const Icon(Icons.auto_awesome, size: 20, color: Colors.amber),
                            onPressed: () {
                              setState(() {
                                _updateNotesCtrl.text = _getDefaultImprovementNotes();
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.auto_awesome, size: 14, color: Colors.amber),
                      label: const Text('Auto-Novedades', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                      onPressed: () => setState(() => _updateNotesCtrl.text = _getDefaultImprovementNotes()),
                    ),
                    ActionChip(
                      label: const Text('+ 3 Teléfonos/Casa', style: TextStyle(fontSize: 10.5)),
                      onPressed: () => _appendNote('Soporte hasta 3 teléfonos por vivienda y cupos adicionales (\$5.000)'),
                    ),
                    ActionChip(
                      label: const Text('+ Expedientes PDF', style: TextStyle(fontSize: 10.5)),
                      onPressed: () => _appendNote('Descarga directa de expedientes policiales en PDF con selección múltiple'),
                    ),
                    ActionChip(
                      label: const Text('+ Alarma Máx. Volumen', style: TextStyle(fontSize: 10.5)),
                      onPressed: () => _appendNote('Sirena a máximo volumen y sonido reforzado de emergencia'),
                    ),
                    ActionChip(
                      label: const Text('+ Manuales HD', style: TextStyle(fontSize: 10.5)),
                      onPressed: () => _appendNote('Manuales de usuario ilustrados HD sin errores de caracteres'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      final url = _qrUrlCtrl.text.trim();
                      final ver = _updateVersionCtrl.text.trim();
                      final notes = _updateNotesCtrl.text.trim();
                      if (url.isNotEmpty) {
                        final code = int.tryParse(ver.replaceAll(RegExp(r'[^0-9]'), '')) ?? 3;
                        await service.publishAppUpdate(
                          versionCode: code,
                          versionName: ver,
                          downloadUrl: url,
                          notes: notes.isNotEmpty ? notes : 'Mejoras y correcciones en la aplicación.',
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Color(0xFF059669),
                              content: Text('¡Actualización publicada! A todos los vecinos les aparecerá el botón para actualizar directamente.'),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.cloud_upload, size: 20),
                    label: const Text(
                      'NOTIFICAR ACTUALIZACIÓN A TODOS LOS VECINOS (SIN QR)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Divider(),
                const SizedBox(height: 6),
                Text(
                  'Opcional: Código QR de respaldo (para instalar por primera vez en un teléfono nuevo):',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? const Color(0xFF93C5FD) : AppColors.brandNavy,
                        ),
                        onPressed: () async {
                          final rawUrl = _qrUrlCtrl.text.trim();
                          if (rawUrl.isNotEmpty) {
                            final directUrl = AlarmSyncService.convertDriveToDirectDownload(rawUrl);
                            _qrUrlCtrl.text = directUrl;
                            await service.setApkDownloadUrl(directUrl);
                            setState(() => _showQr = true);
                          }
                        },
                        icon: const Icon(Icons.qr_code, size: 18),
                        label: const Text('Ver Código QR'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        final rawUrl = _qrUrlCtrl.text.trim();
                        if (rawUrl.isNotEmpty) {
                          final directUrl = AlarmSyncService.convertDriveToDirectDownload(rawUrl);
                          SharePlus.instance.share(
                            ShareParams(
                              text: '📲 Descarga la aplicación Alerta Vecinal Las Galileas desde este enlace directo:\n$directUrl',
                              subject: 'Descarga Alerta Vecinal',
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.share, size: 16),
                      label: const Text('Compartir Enlace'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline, size: 15, color: Color(0xFF2563EB)),
                          const SizedBox(width: 6),
                          const Text(
                            '¿Cómo hacer que descargue e instale directamente?',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '• Al escanear con la cámara: Si tienes Google Drive en el teléfono, Android puede abrir la vista previa de Drive en vez de descargar. Para instalar en 1 toque, abre el enlace en Chrome o toca los 3 puntos (⋮) en Drive y elige "Descargar".\n'
                        '• Alternativa directa recomendada: Puedes subir el APK a GitHub Releases, Dropbox (con ?dl=1) o Firebase Storage para que descargue e instale automáticamente sin pasar por Google Drive.',
                        style: TextStyle(fontSize: 10.5, color: isDark ? Colors.grey.shade300 : const Color(0xFF1E3A8A), height: 1.3),
                      ),
                    ],
                  ),
                ),
                if (_showQr && _qrUrlCtrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          QrImageView(
                            data: AlarmSyncService.convertDriveToDirectDownload(_qrUrlCtrl.text.trim()),
                            version: QrVersions.auto,
                            size: 200.0,
                            backgroundColor: Colors.white,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Escanea con la cámara para descargar',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 3. Manuales de Usuario Oficiales en PDF (Vecinos fácil lectura y Admin)
        Card(
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.menu_book, color: AppColors.steelBlue),
                    SizedBox(width: 8),
                    Text('Manuales de Usuario en PDF', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Documentos completos listos para imprimir o compartir. Redactados con lenguaje claro y letra grande para adultos mayores.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.sageGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => ManualPdfService.exportNeighborManual(),
                        icon: const Icon(Icons.people, size: 18),
                        label: const Text('Manual Vecinos\n(Fácil Lectura)', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? const Color(0xFF2563EB) : AppColors.brandNavy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => ManualPdfService.exportAdminManual(),
                        icon: const Icon(Icons.shield, size: 18),
                        label: const Text('Manual Admin\n(Técnico)', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 4. Selector de Tema Visual (Modo Blanco / Modo Negro)
        Card(
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.palette_outlined, color: Colors.purple),
                    SizedBox(width: 8),
                    Text('Apariencia de la Aplicación', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Elige la paleta de colores preferida para la interfaz (Modo Blanco Claro o Modo Negro Oscuro).',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    ThemeService().isDarkMode ? Icons.dark_mode : Icons.light_mode,
                    color: ThemeService().isDarkMode ? Colors.amber : Colors.orange,
                  ),
                  title: Text(
                    ThemeService().isDarkMode ? 'Modo Oscuro (Negro)' : 'Modo Claro (Blanco)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    ThemeService().isDarkMode ? 'Fondo oscuro ideal para la noche' : 'Fondo blanco clásico de alta visibilidad',
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: ThemeService().isDarkMode,
                  onChanged: (val) async {
                    await ThemeService().setDarkMode(val);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 5. Control General de Alarma Comunitaria
        Card(
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.crisis_alert, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Control General de Alarma', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
                  onPressed: _triggerTestAlert,
                  icon: const Icon(Icons.volume_up),
                  label: const Text('Disparar Alarma de Prueba Comunitaria'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                  onPressed: _cancelActiveAlert,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Cancelar Alarma Activa General'),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 6. Copia de Seguridad y Exportación JSON
        Card(
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.backup, color: Colors.teal),
                    SizedBox(width: 8),
                    Text('Copia de Seguridad del Sistema', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Exporta todos los vecinos registrados, reportes de incidentes y botones en formato JSON para respaldo en computador.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                  onPressed: () async {
                    final data = await service.exportAllDataJson();
                    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
                    await SharePlus.instance.share(
                      ShareParams(
                        text: jsonStr,
                        subject: 'Respaldo_Centinela_Urbano_${DateFormat('yyyyMMdd').format(DateTime.now())}.json',
                      ),
                    );
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Exportar Respaldo JSON'),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 8. Mantenimiento y Limpieza de Reportes
        Card(
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.cleaning_services, color: Colors.blueGrey),
                    SizedBox(width: 8),
                    Text('Mantenimiento y Depuración', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Limpia reportes antiguos o de prueba para mantener la base de datos liviana y rápida.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Depurar reportes antiguos'),
                              content: const Text('¿Deseas eliminar reportes con más de 30 días de antigüedad?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            final deleted = await service.clearOldReports(days: 30);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Se eliminaron $deleted reportes antiguos.')),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.history, size: 16),
                        label: const Text('Borrar > 30 días', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.orange.shade800),
                        onPressed: () async {
                          final deleted = await service.clearTestReports();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Se eliminaron $deleted reportes de prueba.')),
                            );
                          }
                        },
                        icon: const Icon(Icons.delete_sweep, size: 16),
                        label: const Text('Borrar Pruebas', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 9. Restablecer Botones Predeterminados
        Card(
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.restore, color: AppColors.brandNavyOf(context)),
                    const SizedBox(width: 8),
                    const Text('Botones Predeterminados', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Si los botones se desconfiguraron, vuelve a colocar los 3 botones originales (Robo, Incendio y Médica).',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await service.restoreDefaultButtons();
                    setState(() {});
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Botones por defecto restaurados en Firebase.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Restablecer Botones'),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 10. Optimización de Batería y Permisos Android
        Card(
          elevation: 1.5,
          color: _isIgnoringBattery ? null : Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.battery_charging_full, color: _isIgnoringBattery ? Colors.green : Colors.deepOrange),
                    const SizedBox(width: 8),
                    const Text('Optimización de Batería Android', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _isIgnoringBattery
                      ? '✅ Permiso concedido: La aplicación tiene permiso para funcionar en segundo plano y encender la pantalla durante emergencias.'
                      : '⚠️ La batería está optimizada por Android. Para asegurar que la sirena suene con la pantalla apagada, activa la exclusión.',
                  style: TextStyle(fontSize: 12, color: _isIgnoringBattery ? Colors.green.shade800 : Colors.deepOrange.shade800),
                ),
                if (!_isIgnoringBattery) ...[
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                    onPressed: () async {
                      await NativeAlertService.requestIgnoreBatteryOptimizations();
                      await Future.delayed(const Duration(seconds: 1));
                      final bat = await NativeAlertService.isIgnoringBatteryOptimizations();
                      if (mounted) setState(() => _isIgnoringBattery = bat);
                    },
                    child: const Text('Activar Exclusión de Batería'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
