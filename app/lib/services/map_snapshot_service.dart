import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Servicio para generar fotografías satelitales y mapas tácticos realistas
/// basados en teselas reales de OpenStreetMap / CartoDB / Esri Satellite,
/// con dibujo de marcador pericial y metadatos del incidente.
class MapSnapshotService {
  static final Map<String, Uint8List> _tileCache = {};

  /// Genera una imagen PNG realista (600x300 px) del mapa centrada en [lat], [lng]
  /// con el pin pericial y ficha informativa superpuesta.
  static Future<Uint8List> generateRealisticMapSnapshot({
    required double lat,
    required double lng,
    required String address,
    required String incidentType,
    required String code,
    int zoom = 17,
    bool satellite = false,
  }) async {
    const int targetWidth = 600;
    const int targetHeight = 300;

    // Intentar descargar teselas reales y coserlas en el Canvas
    try {
      final realMap = await _buildStitchedTileMap(
        lat: lat,
        lng: lng,
        zoom: zoom,
        width: targetWidth,
        height: targetHeight,
        satellite: satellite,
      ).timeout(const Duration(seconds: 4));

      if (realMap != null) {
        return await _overlayIncidentMetadata(
          baseImage: realMap,
          width: targetWidth,
          height: targetHeight,
          lat: lat,
          lng: lng,
          address: address,
          incidentType: incidentType,
          code: code,
          isRealTile: true,
        );
      }
    } catch (_) {
      // Si no hay internet o falla la descarga, usar renderizado táctico de alta resolución
    }

    return _generateFallbackRealisticMap(
      width: targetWidth,
      height: targetHeight,
      lat: lat,
      lng: lng,
      address: address,
      incidentType: incidentType,
      code: code,
    );
  }

  /// Descarga 4 o 6 teselas vecinas y las une en una imagen continua
  static Future<ui.Image?> _buildStitchedTileMap({
    required double lat,
    required double lng,
    required int zoom,
    required int width,
    required int height,
    required bool satellite,
  }) async {
    final n = math.pow(2.0, zoom).toDouble();
    final xExact = ((lng + 180.0) / 360.0) * n;
    final latRad = lat * math.pi / 180.0;
    final yExact = (1.0 - (math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi)) / 2.0 * n;

    final xCenterTile = xExact.floor();
    final yCenterTile = yExact.floor();
    final offsetX = (xExact - xCenterTile) * 256.0;
    final offsetY = (yExact - yCenterTile) * 256.0;

    // Matriz de 3x2 teselas para cubrir completamente los 600x300 px
    final List<(int, int, double, double)> tilesToLoad = [];
    final centerPixelX = width / 2.0;
    final centerPixelY = height / 2.0;

    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        final tx = xCenterTile + dx;
        final ty = yCenterTile + dy;
        final px = centerPixelX + (dx * 256.0) - offsetX;
        final py = centerPixelY + (dy * 256.0) - offsetY;
        tilesToLoad.add((tx, ty, px, py));
      }
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

    // Fondo neutro
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = satellite ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
    );

    int loadedCount = 0;

    for (final t in tilesToLoad) {
      final img = await _fetchTileImage(t.$1, t.$2, zoom, satellite: satellite);
      if (img != null) {
        canvas.drawImage(img, Offset(t.$3, t.$4), Paint());
        loadedCount++;
      }
    }

    if (loadedCount == 0) return null;

    final picture = recorder.endRecording();
    return picture.toImage(width, height);
  }

  /// Descarga o recupera de caché una tesela individual
  static Future<ui.Image?> _fetchTileImage(int x, int y, int z, {required bool satellite}) async {
    final cacheKey = '$satellite-$z-$x-$y';
    Uint8List? bytes = _tileCache[cacheKey];

    if (bytes == null) {
      final String url = satellite
          ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/$z/$y/$x'
          : 'https://tile.openstreetmap.org/$z/$y/$x.png';

      try {
        final resp = await http.get(
          Uri.parse(url),
          headers: {'User-Agent': 'AlertaVecinalApp/1.0 (Comunidad Las Galileas Coronel)'},
        ).timeout(const Duration(seconds: 4));

        if (resp.statusCode == 200 && resp.bodyBytes.length > 200) {
          bytes = resp.bodyBytes;
          if (_tileCache.length < 120) {
            _tileCache[cacheKey] = bytes;
          }
        }
      } catch (_) {}
    }

    if (bytes == null) return null;

    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  /// Dibuja sobre la imagen del mapa el Pin pericial, regla métrica y rótulo oficial
  static Future<Uint8List> _overlayIncidentMetadata({
    required ui.Image baseImage,
    required int width,
    required int height,
    required double lat,
    required double lng,
    required String address,
    required String incidentType,
    required String code,
    required bool isRealTile,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

    // 1. Dibujar mapa base real
    canvas.drawImage(baseImage, Offset.zero, Paint());

    // 2. Viñeta perimetral suave
    final vignettePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), vignettePaint);

    final centerX = width / 2.0;
    final centerY = height / 2.0;

    // 3. Onda de impacto / radio de alerta comunitaria
    final pulsePaint = Paint()
      ..color = const Color(0xFFDC2626).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX, centerY), 48, pulsePaint);

    final pulseBorder = Paint()
      ..color = const Color(0xFFDC2626)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(centerX, centerY), 48, pulseBorder);

    // 4. Pin pericial gigante con sombra
    final shadowPaint = Paint()..color = const Color(0x66000000);
    canvas.drawCircle(Offset(centerX, centerY + 3), 10, shadowPaint);

    final pinBodyPaint = Paint()..color = const Color(0xFFDC2626);
    canvas.drawCircle(Offset(centerX, centerY - 6), 14, pinBodyPaint);

    final pinInnerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(centerX, centerY - 6), 5.5, pinInnerPaint);

    // 5. Etiqueta flotante con el lugar exacto del hecho
    final labelBg = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(centerX, centerY - 32), width: 220, height: 26),
      const Radius.circular(6),
    );
    canvas.drawRRect(labelBg, Paint()..color = const Color(0xFF0F172A));
    canvas.drawRRect(labelBg, Paint()..color = const Color(0xFFDC2626)..style = PaintingStyle.stroke..strokeWidth = 1.4);

    _drawCanvasText(
      canvas,
      '📍 $address',
      Offset(centerX - 102, centerY - 39),
      fontSize: 10,
      bold: true,
      color: Colors.white,
      maxWidth: 204,
    );

    // 6. Rótulo institucional superior (Membrete oficial policial)
    final headerRRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(10, 10, 310, 38),
      const Radius.circular(6),
    );
    canvas.drawRRect(headerRRect, Paint()..color = const Color(0xEE0F172A));
    canvas.drawRRect(headerRRect, Paint()..color = const Color(0xFF1E3A8A)..style = PaintingStyle.stroke..strokeWidth = 1.0);

    _drawCanvasText(
      canvas,
      '🚨 CROQUIS GEOESPACIAL DEL INCIDENTE',
      const Offset(18, 14),
      fontSize: 8.5,
      bold: true,
      color: const Color(0xFFFBBF24),
    );
    _drawCanvasText(
      canvas,
      '$incidentType • $code • GPS: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
      const Offset(18, 29),
      fontSize: 7.5,
      color: Colors.white,
    );

    // 7. Rosa de los vientos (Norte)
    final northRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(width - 48, 10, 38, 38),
      const Radius.circular(8),
    );
    canvas.drawRRect(northRRect, Paint()..color = const Color(0xEE0F172A));
    _drawCanvasText(canvas, 'N', Offset(width - 33, 13), fontSize: 11, bold: true, color: const Color(0xFFDC2626));
    _drawCanvasText(canvas, '▲', Offset(width - 34, 25), fontSize: 13, bold: true, color: Colors.white);

    // 8. Marca de fuente cartográfica
    final badgeRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(10, height - 24, 180, 18),
      const Radius.circular(4),
    );
    canvas.drawRRect(badgeRRect, Paint()..color = const Color(0xCC0F172A));
    _drawCanvasText(
      canvas,
      isRealTile ? '🛰️ Cartografía Oficial Las Galileas' : '🗺️ Croquis Georreferenciado Oficial',
      Offset(16, (height - 21).toDouble()),
      fontSize: 7.0,
      color: const Color(0xFF94A3B8),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Generador táctico realista offline con las calles y manzanas de Las Galileas
  static Future<Uint8List> _generateFallbackRealisticMap({
    required int width,
    required int height,
    required double lat,
    required double lng,
    required String address,
    required String incidentType,
    required String code,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

    // Fondo estilo mapa claro
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = const Color(0xFFF8FAFC));

    // Manzanas residenciales
    final blockPaint = Paint()..color = const Color(0xFFE2E8F0);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(20, 20, 180, 70), const Radius.circular(4)), blockPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(20, 110, 180, 70), const Radius.circular(4)), blockPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(20, 200, 180, 80), const Radius.circular(4)), blockPaint);

    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(220, 20, 160, 70), const Radius.circular(4)), blockPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(220, 110, 160, 70), const Radius.circular(4)), blockPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(220, 200, 160, 80), const Radius.circular(4)), blockPaint);

    // Cancha y Plaza verde
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(400, 90, 180, 110), const Radius.circular(6)), Paint()..color = const Color(0xFFDCFCE7));
    _drawCanvasText(canvas, '⚽ PLAZA Y MULTICANCHA', const Offset(415, 138), fontSize: 8.5, bold: true, color: const Color(0xFF166534));

    // Calles asfaltadas
    final roadPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 90, width.toDouble(), 20), roadPaint); // Catrileo
    canvas.drawRect(Rect.fromLTWH(0, 180, width.toDouble(), 20), roadPaint); // Pasaje
    canvas.drawRect(Rect.fromLTWH(200, 0, 20, height.toDouble()), roadPaint); // Av. Las Torres
    canvas.drawRect(Rect.fromLTWH(380, 0, 20, height.toDouble()), roadPaint); // Paillao

    _drawCanvasText(canvas, 'CALLE CATRILEO', const Offset(40, 95), fontSize: 7.5, bold: true, color: const Color(0xFF475569));
    _drawCanvasText(canvas, 'AV. LAS TORRES', const Offset(40, 185), fontSize: 7.5, bold: true, color: const Color(0xFF475569));
    _drawCanvasText(canvas, 'PAILLAO', const Offset(204, 30), fontSize: 6.5, bold: true, color: const Color(0xFF475569));

    // Pin de incidente
    const centerX = 300.0;
    const centerY = 150.0;

    canvas.drawCircle(const Offset(centerX, centerY), 45, Paint()..color = const Color(0x33DC2626));
    canvas.drawCircle(const Offset(centerX, centerY), 45, Paint()..color = const Color(0xFFDC2626)..style = PaintingStyle.stroke..strokeWidth = 2);
    canvas.drawCircle(const Offset(centerX, centerY), 12, Paint()..color = const Color(0xFFDC2626));
    canvas.drawCircle(const Offset(centerX, centerY), 4, Paint()..color = Colors.white);

    // Rótulo superior
    final headerRect = RRect.fromRectAndRadius(const Rect.fromLTWH(10, 10, 280, 36), const Radius.circular(6));
    canvas.drawRRect(headerRect, Paint()..color = const Color(0xFF0F172A));
    _drawCanvasText(canvas, '🚨 CROQUIS POLICIAL VILLA ESCUADRÓN GALILEA', const Offset(18, 14), fontSize: 8.5, bold: true, color: const Color(0xFFFBBF24));
    _drawCanvasText(canvas, 'Lugar: $address • GPS: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}', const Offset(18, 28), fontSize: 7.5, color: Colors.white);

    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  static void _drawCanvasText(
    Canvas canvas,
    String text,
    Offset offset, {
    required double fontSize,
    Color color = Colors.black,
    bool bold = false,
    double? maxWidth,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: maxWidth ?? double.infinity);
    tp.paint(canvas, offset);
  }
}
