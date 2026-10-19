import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ManualPdfService {
  // ===========================================================================
  // CARGADOR SEGURO DE CAPTURAS REALES DESDE ASSETS
  // ===========================================================================
  static Future<Uint8List?> _loadManualImage(String assetName) async {
    try {
      final data = await rootBundle.load('assets/images/manual/$assetName');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (e) {
      debugPrint('No se pudo cargar asset $assetName: $e');
      return null;
    }
  }

  // ===========================================================================
  // 1. MANUAL ILUSTRADO PARA VECINOS Y ADULTOS MAYORES (CON CAPTURAS REALES)
  // ===========================================================================
  static Future<void> exportNeighborManual() async {
    // 1. Cargar las capturas reales enviadas por la comunidad (sin mapa)
    final imgTop = await _loadManualImage('vecino_inicio_superior.jpg');
    final imgButtons = await _loadManualImage('vecino_botones_panico.jpg');
    final imgConfirm = await _loadManualImage('vecino_confirmacion_alerta.jpg');
    final imgGuide = await _loadManualImage('vecino_guia_popup.jpg');
    final imgHistory = await _loadManualImage('vecino_historial_reportes.jpg');

    final pdf = pw.Document();

    // -------------------------------------------------------------------------
    // PÁGINA 1: PANTALLA PRINCIPAL Y CENTRALES DE EMERGENCIA (1-TOQUE)
    // -------------------------------------------------------------------------
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(
                title: 'CENTINELA URBANO - ALERTA VECINAL',
                subtitle: 'MANUAL ILUSTRADO PARA VECINOS Y ADULTOS MAYORES (VILLA ESCUADRON GALILEA)',
                headerColorHex: '#1E293B',
                badgeText: 'GUIA VISUAL PASO A PASO CON FOTOS REALES',
              ),
              pw.SizedBox(height: 8),

              _buildChapterTitle('CAPITULO 1: PANTALLA PRINCIPAL Y TELEFONOS DE EMERGENCIA DE 1-TOQUE'),
              pw.SizedBox(height: 6),

              _buildCalloutItem(
                number: '1',
                title: 'BARRA SUPERIOR (LOGO, DIRECCION Y AJUSTES)',
                action: 'Muestra tu direccion registrada y permite configurar el aspecto visual de la aplicacion.',
                instruction: 'Veras tu pasaje y numero de casa. Toca el icono de tuerca a la derecha para alternar entre Modo Claro (dia) y Modo Oscuro (noche).',
                badgeColor: PdfColors.indigo900,
              ),
              _buildCalloutItem(
                number: '2',
                title: 'ESTADO DEL VECINO Y CORRECCION DE DATOS',
                action: 'Indica "EN LINEA | PROTEGIDO" con tu nombre y calle.',
                instruction: 'Si tu nombre o numero esta mal escrito, pulsa el icono de lapiz a la derecha. Tienes 3 intentos para corregirlo tu mismo.',
                badgeColor: PdfColors.blue800,
              ),
              _buildCalloutItem(
                number: '3',
                title: 'CENTRALES DE EMERGENCIA DE 1-TOQUE (LLAMADA INMEDIATA)',
                action: 'Comunica directo con las autoridades sin buscar en la agenda del telefono.',
                instruction: '[133 Carabineros] policial | [132 Bomberos] incendios | [131 SAMU] ambulancia | [1414 Seguridad Ciudadana] patrulla comunal de Coronel.',
                tip: 'Disenado para personas mayores: un solo toque y el celular marca automaticamente.',
                badgeColor: PdfColors.green800,
              ),

              pw.SizedBox(height: 8),

              // Captura Grande Centrada
              if (imgTop != null) ...[
                pw.Center(
                  child: _buildScreenshotFrame(imgTop, height: 380),
                ),
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text(
                    'Figura 1: Pantalla Principal con identificacion comunitaria y centrales de emergencia de 1-toque.',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                  ),
                ),
              ],

              pw.Spacer(),
              _buildPageFooter('Comite de Seguridad Vecinal - Villa Escuadron Galilea, Coronel (Pagina 1 de 4)'),
            ],
          );
        },
      ),
    );

    // -------------------------------------------------------------------------
    // PÁGINA 2: BOTONERA DE PÁNICO Y EVIDENCIA FOTOGRÁFICA
    // -------------------------------------------------------------------------
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildChapterTitle('CAPITULO 2: BOTONERA DE PANICO RAPIDO Y MODULO DE EVIDENCIA'),
              pw.SizedBox(height: 6),

              _buildCalloutItem(
                number: '1',
                title: '[PANICO] ROBO / INTRUSION (Boton Rojo)',
                action: 'Dispara sirena de maxima potencia en toda la villa avisando robo en curso.',
                instruction: 'Presionalo si ves intrusos en patios, techos o forzando portones. No exige escribir nada, suena en 1 toque.',
                badgeColor: PdfColors.red800,
              ),
              _buildCalloutItem(
                number: '2',
                title: '[URGENCIA] INCENDIO (Boton Naranja)',
                action: 'Alerta a todos los vecinos por fuego, humo espeso o fuga de gas.',
                instruction: 'Usalo para que los vecinos salgan con extintores y mangueras mientras acude Bomberos.',
                badgeColor: PdfColors.orange800,
              ),
              _buildCalloutItem(
                number: '3',
                title: '[MEDICO] ACCIDENTE MEDICO (Boton Azul)',
                action: 'Pide auxilio urgente a la comunidad por caidas, descompensaciones o paros de vecinos.',
                instruction: 'Activalo de inmediato para asistencia vecinal mientras arriba la ambulancia.',
                badgeColor: PdfColors.blue800,
              ),
              _buildCalloutItem(
                number: '4',
                title: '[PREVENCION] SOSPECHOSO (Boton Verde)',
                action: 'Aviso preventivo para merodeo de personas o vehiculos extranos en los pasajes.',
                instruction: 'Permite advertir a los vecinos para encender luces exteriores y estar atentos.',
                badgeColor: PdfColors.teal800,
              ),
              _buildCalloutItem(
                number: '5',
                title: 'MODULO EVIDENCIA FOTOGRAFICA Y GUIA VECINOS',
                action: 'Toma fotos de patentes o sospechosos y las envia al WhatsApp del Administrador.',
                instruction: 'Pulsa [Tomar Foto] o [Galeria]. La app redacta el informe en el pie de foto automaticamente.',
                tip: 'El boton flotante "Guia Vecinos" (abajo a la izquierda) te permite descargar este manual cuando lo necesites.',
                badgeColor: PdfColors.indigo900,
              ),

              pw.SizedBox(height: 8),

              // Captura Grande Centrada
              if (imgButtons != null) ...[
                pw.Center(
                  child: _buildScreenshotFrame(imgButtons, height: 380),
                ),
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text(
                    'Figura 2: Botonera de Panico de 1-Toque y Modulo de Captura de Fotos de Evidencia.',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                  ),
                ),
              ],

              pw.Spacer(),
              _buildPageFooter('Comite de Seguridad Vecinal - Villa Escuadron Galilea, Coronel (Pagina 2 de 4)'),
            ],
          );
        },
      ),
    );

    // -------------------------------------------------------------------------
    // PÁGINA 3: DÓNDE OCURRE EL INCIDENTE Y CONFIRMACIÓN (SIN FOTO DE MAPA)
    // -------------------------------------------------------------------------
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildChapterTitle('CAPITULO 3: SELECCION DE UBICACION DEL INCIDENTE Y CONFIRMACION'),
              pw.SizedBox(height: 6),

              _buildCalloutItem(
                number: '1',
                title: 'OPCION 1: "EN MI DOMICILIO REGISTRADO"',
                action: 'Selecciona tu casa predeterminada (ej: Pasaje Los Aromos #142) en 1 segundo.',
                instruction: 'Es la opcion mas rapida y recomendada cuando la emergencia ocurre en tu propio hogar.',
                badgeColor: PdfColors.indigo900,
              ),
              _buildCalloutItem(
                number: '2',
                title: 'OPCION 2: "FUERA DE CASA / EN LA VIA PUBLICA"',
                action: 'Toma la senal satelital GPS de tu celular o te permite ingresar el pasaje.',
                instruction: 'Usalo si el hecho ocurre frente a tu casa, en la plaza comunitaria o en un pasaje vecino.',
                badgeColor: PdfColors.orange900,
              ),
              _buildCalloutItem(
                number: '3',
                title: 'OPCION 3: "MARCAR EN MAPA INTERACTIVO"',
                action: 'Abre el plano interactivo de la villa sin salir de la aplicacion.',
                instruction: 'Toca directamente la casa o calle en pantalla y pulsa "Confirmar Ubicacion" para fijar las coordenadas.',
                tip: 'El mapa centra automaticamente en tu pasaje con el boton "Usar mi GPS".',
                badgeColor: PdfColors.teal900,
              ),
              _buildCalloutItem(
                number: '4',
                title: 'BOTON VERDE: "HACER SONAR ALARMA"',
                action: 'Confirma la alerta y activa inmediatamente la sirena en todos los celulares de la villa.',
                instruction: 'Presiona el boton para confirmar. La red de proteccion vecinal se activara al instante.',
                badgeColor: PdfColors.red900,
              ),

              pw.SizedBox(height: 8),

              // Captura Grande Centrada de la Confirmación (Sin Mapa)
              if (imgConfirm != null) ...[
                pw.Center(
                  child: _buildScreenshotFrame(imgConfirm, height: 380),
                ),
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text(
                    'Figura 3: Selector rapido de ubicacion (Domicilio, Via Publica o Mapa) y boton de confirmacion.',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                  ),
                ),
              ],

              pw.Spacer(),
              _buildPageFooter('Comite de Seguridad Vecinal - Villa Escuadron Galilea, Coronel (Pagina 3 de 4)'),
            ],
          );
        },
      ),
    );

    // -------------------------------------------------------------------------
    // PÁGINA 4: QUÉ HACER CUANDO SUENA LA ALARMA Y REGLA DE ORO
    // -------------------------------------------------------------------------
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildChapterTitle('CAPITULO 4: QUE HACER CUANDO SUENA LA ALARMA Y REGLA DE ORO'),
              pw.SizedBox(height: 6),

              _buildCalloutItem(
                number: '1',
                title: 'SIRENA A MAXIMO VOLUMEN CON IDENTIFICACION',
                action: 'Tu celular encendera la pantalla y sonara aunque este en silencio o vibrador.',
                instruction: 'Veras el nombre del vecino que activo la alarma y su casa en letras gigantes destacadas.',
                badgeColor: PdfColors.red900,
              ),
              _buildCalloutItem(
                number: '2',
                title: 'BOTON "ABRIR EN GOOGLE MAPS"',
                action: 'Traza la ruta guiada para acudir en auxilio del vecino afectado.',
                instruction: 'Indica a cuantos metros esta el incidente y el camino mas rapido dentro de la villa.',
                badgeColor: PdfColors.blue900,
              ),
              _buildCalloutItem(
                number: '3',
                title: 'BOTON "SILENCIAR ALARMA"',
                action: 'Apaga el sonido ensordecedor para permitirte hablar o coordinar por telefono.',
                instruction: 'No borra los datos. La informacion del vecino sigue fija en tu pantalla.',
                badgeColor: PdfColors.grey900,
              ),

              pw.SizedBox(height: 6),

              // Tarjeta Regla de Oro
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#FEF3C7'),
                  border: pw.Border.all(color: PdfColor.fromHex('#D97706'), width: 1.5),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '[REGLA DE ORO DE SEGURIDAD VECINAL]:',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: PdfColor.fromHex('#92400E')),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      '- SI ESTAS SOLO(A) EN TU CASA: NUNCA SALGAS A ENFRENTAR A LOS DELINCUENTES.\n'
                      '- Asegura puertas, prende luces exteriores, haz ruido seguro y espera a que los vecinos salgan en grupo o llegue la patrulla de Carabineros (133).',
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.black),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 8),

              // Dos Capturas Grandes Lado a Lado (Ventana de Emergencia e Historial)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  if (imgGuide != null)
                    pw.Column(
                      children: [
                        _buildScreenshotFrame(imgGuide, height: 320),
                        pw.SizedBox(height: 3),
                        pw.Text('Figura 4: Ventana de Emergencia Activa.', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                      ],
                    ),
                  if (imgGuide != null && imgHistory != null) pw.SizedBox(width: 24),
                  if (imgHistory != null)
                    pw.Column(
                      children: [
                        _buildScreenshotFrame(imgHistory, height: 320),
                        pw.SizedBox(height: 3),
                        pw.Text('Figura 5: Historial de Incidentes.', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                      ],
                    ),
                ],
              ),

              pw.Spacer(),
              _buildPageFooter('Comite de Seguridad Vecinal - Villa Escuadron Galilea, Coronel (Pagina 4 de 4)'),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Manual_Vecinos_Villa_Escuadron_Galilea.pdf',
    );
  }

  // ===========================================================================
  // 2. MANUAL TÉCNICO Y OPERATIVO DEL ADMINISTRADOR (CON CAPTURAS REALES)
  // ===========================================================================
  static Future<void> exportAdminManual() async {
    // 1. Cargar las capturas reales del panel administrador
    final imgRoster = await _loadManualImage('admin_padron_vecinos.jpg');
    final imgButtonsList = await _loadManualImage('admin_gestion_botones.jpg');
    final imgButtonCreate = await _loadManualImage('admin_crear_boton.jpg');
    final imgReportsList = await _loadManualImage('admin_lista_reportes.jpg');
    final imgQrExpediente = await _loadManualImage('admin_qr_expediente.jpg');
    final imgSystemTop = await _loadManualImage('admin_sistema_comunicados.jpg');
    final imgSystemMiddle = await _loadManualImage('admin_sistema_controles.jpg');
    final imgSystemOta = await _loadManualImage('admin_sistema_actualizaciones.jpg');
    final imgSystemBottom = await _loadManualImage('admin_sistema_mantenimiento.jpg');

    final pdf = pw.Document();

    // -------------------------------------------------------------------------
    // PÁGINA A1: PADRÓN COMUNITARIO Y CONTROL DE VECINOS
    // -------------------------------------------------------------------------
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(
                title: 'CENTINELA URBANO - PANEL ADMINISTRADOR',
                subtitle: 'MANUAL OPERATIVO, TECNICO Y POLICIAL DEL SISTEMA (VILLA ESCUADRON GALILEA)',
                headerColorHex: '#0F172A',
                badgeText: 'USO EXCLUSIVO ADMINISTRADOR / DIRECTIVA',
              ),
              pw.SizedBox(height: 8),

              _buildChapterTitle('MODULO 1: PADRON COMUNITARIO DE VECINOS Y CONTROL DE PLANES'),
              pw.SizedBox(height: 6),

              _buildCalloutItem(
                number: '1',
                title: 'RESUMEN DEL PADRON Y BOTON "NOMINA PDF"',
                action: 'Muestra total de vecinos (Activos / Desactivados) y genera la nomina imprimible.',
                instruction: 'Pulsa [Nomina PDF] para exportar la lista oficial con todas las casas, nombres y estados para reuniones.',
                badgeColor: PdfColors.indigo900,
              ),
              _buildCalloutItem(
                number: '2',
                title: 'BLINDAJE DE LA CUENTA ADMINISTRADOR',
                action: 'Proteccion exclusiva contra bloqueos accidentales.',
                instruction: 'Tu cuenta muestra el badge [ADMIN] y [Cuenta Protegida]. No tiene botones de auto-desactivacion.',
                badgeColor: PdfColors.blue800,
              ),
              _buildCalloutItem(
                number: '3',
                title: 'BOTON [EDITAR DATOS] Y RESTABLECER INTENTOS',
                action: 'Modifica nombre, apellidos y direccion del vecino en la base de datos.',
                instruction: 'Usalo si un vecino se equivoco de pasaje o si agoto sus 3 intentos de autocorreccion.',
                badgeColor: PdfColors.teal800,
              ),
              _buildCalloutItem(
                number: '4',
                title: 'BOTON [PLAN / PRUEBA (DIAS RESTANTES)]',
                action: 'Control de vigencia del periodo de prueba o cuota comunitaria.',
                instruction: 'Cada vecino recibe 30 dias de prueba automatica. El temporizador descuenta dias y horas en vivo.',
                badgeColor: PdfColors.orange900,
              ),
              _buildCalloutItem(
                number: '5',
                title: 'BOTONES [DESACTIVAR] Y [ELIMINAR]',
                action: 'Control de acceso a la red de seguridad.',
                instruction: '[Desactivar]: Suspende la app del vecino temporalmente. [Eliminar]: Baja definitiva de Firebase.',
                badgeColor: PdfColors.red800,
              ),

              pw.SizedBox(height: 8),

              // Captura Grande Centrada
              if (imgRoster != null) ...[
                pw.Center(
                  child: _buildScreenshotFrame(imgRoster, height: 380),
                ),
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text(
                    'Figura A1: Padron Comunitario con gestion de residentes, estados y control de periodos de prueba.',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                  ),
                ),
              ],

              pw.Spacer(),
              _buildPageFooter('Panel Administrador - Villa Escuadron Galilea, Coronel (Pagina 1 de 4)'),
            ],
          );
        },
      ),
    );

    // -------------------------------------------------------------------------
    // PÁGINA A2: GESTIÓN Y CREACIÓN DE BOTONES PERSONALIZADOS
    // -------------------------------------------------------------------------
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildChapterTitle('MODULO 2: GESTION Y CREACION DE BOTONES DE ALERTA'),
              pw.SizedBox(height: 6),

              _buildCalloutItem(
                number: '1',
                title: 'BOTONES PREDETERMINADOS [PROTEGIDOS]',
                action: 'Los 3 botones vitales (Robo, Incendio y Medico) son inamovibles por seguridad comunitaria.',
                instruction: 'Garantiza que adultos mayores siempre encuentren las alertas basicas en la misma posicion.',
                badgeColor: PdfColors.indigo900,
              ),
              _buildCalloutItem(
                number: '2',
                title: 'BOTON AZUL "+ CREAR NUEVO BOTON DE ALERTA"',
                action: 'Permite agregar alertas especializadas para la villa (ej: Portonazo, Ruido Molesto, Inundacion).',
                instruction: 'Toca el boton azul superior para abrir el formulario creador.',
                badgeColor: PdfColors.blue800,
              ),
              _buildCalloutItem(
                number: '3',
                title: 'CAMPOS DEL CREADOR DE BOTONES',
                action: 'Personalizacion grafica y operativa completa.',
                instruction: 'Define Titulo, Subtitulo, selecciona icono de la matriz, elige color de paleta y activa si exige fotos o descripcion.',
                badgeColor: PdfColors.teal800,
              ),
              _buildCalloutItem(
                number: '4',
                title: 'ELIMINAR BOTON PERSONALIZADO',
                action: 'Permite retirar cualquier boton creado cuando ya no sea necesario.',
                instruction: 'Los botones creados cuentan con icono de papelera roja para borrarlos en 1 toque.',
                badgeColor: PdfColors.red800,
              ),

              pw.SizedBox(height: 8),

              // Dos Capturas Grandes Lado a Lado
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  if (imgButtonsList != null)
                    pw.Column(
                      children: [
                        _buildScreenshotFrame(imgButtonsList, height: 350),
                        pw.SizedBox(height: 3),
                        pw.Text('Fig. A2: Gestion de Botonera Comunitaria.', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                      ],
                    ),
                  if (imgButtonsList != null && imgButtonCreate != null) pw.SizedBox(width: 20),
                  if (imgButtonCreate != null)
                    pw.Column(
                      children: [
                        _buildScreenshotFrame(imgButtonCreate, height: 350),
                        pw.SizedBox(height: 3),
                        pw.Text('Fig. A3: Creador de Nuevos Botones.', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                      ],
                    ),
                ],
              ),

              pw.Spacer(),
              _buildPageFooter('Panel Administrador - Villa Escuadron Galilea, Coronel (Pagina 2 de 4)'),
            ],
          );
        },
      ),
    );

    // -------------------------------------------------------------------------
    // PÁGINA A3: REPORTES POLICIALES, EXPEDIENTES Y CÓDIGOS QR
    // -------------------------------------------------------------------------
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildChapterTitle('MODULO 3: GESTION DE REPORTES, EXPEDIENTES PDF Y QR POLICIAL'),
              pw.SizedBox(height: 6),

              _buildCalloutItem(
                number: '1',
                title: 'FILTROS TEMPORALES Y ACCIONES MASIVAS',
                action: 'Filtra por Semana, Mes, Ano o Todos con 1 toque.',
                instruction: '[Descargar PDF] genera el expediente consolidado. [Imprimir Todo] manda directo a papel.',
                badgeColor: PdfColors.indigo900,
              ),
              _buildCalloutItem(
                number: '2',
                title: 'SELECCION MULTIPLE POR CHECKBOX Y DESCARGA DIRECTA',
                action: 'Marca varios reportes con las casillas de verificacion para generar un acta a medida.',
                instruction: 'Al generar el QR con multiples reportes seleccionados, el sistema descarga automaticamente el PDF de los incidentes elegidos.',
                badgeColor: PdfColors.blue800,
              ),
              _buildCalloutItem(
                number: '3',
                title: 'CODIGO QR DE EXPEDIENTE PARA CARABINEROS Y PDI',
                action: 'Muestra en terreno un QR gigante con folios #REP, nombres, horas y coordenadas satelitales.',
                instruction: 'La patrulla escanea el QR con su celular o pulsas "Descargar Expediente PDF" para entregarlo por WhatsApp.',
                tip: 'Las fotos de evidencia tomadas por los vecinos se descargan e incrustan en cuadricula pericial.',
                badgeColor: PdfColors.purple800,
              ),
              _buildCalloutItem(
                number: '4',
                title: 'BOTON "ADJUNTAR FOTO AL REPORTE"',
                action: 'Permite al administrador sumar fotografias adicionales recibidas por canales externos.',
                instruction: 'Adjunta fotos de peritajes para que aparezcan en el documento policial final.',
                badgeColor: PdfColors.teal800,
              ),

              pw.SizedBox(height: 8),

              // Dos Capturas Grandes Lado a Lado
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  if (imgReportsList != null)
                    pw.Column(
                      children: [
                        _buildScreenshotFrame(imgReportsList, height: 350),
                        pw.SizedBox(height: 3),
                        pw.Text('Fig. A4: Pestana Reportes con Checkboxes.', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                      ],
                    ),
                  if (imgReportsList != null && imgQrExpediente != null) pw.SizedBox(width: 20),
                  if (imgQrExpediente != null)
                    pw.Column(
                      children: [
                        _buildScreenshotFrame(imgQrExpediente, height: 350),
                        pw.SizedBox(height: 3),
                        pw.Text('Fig. A5: QR y Expediente para Carabineros.', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                      ],
                    ),
                ],
              ),

              pw.Spacer(),
              _buildPageFooter('Panel Administrador - Villa Escuadron Galilea, Coronel (Pagina 3 de 4)'),
            ],
          );
        },
      ),
    );

    // -------------------------------------------------------------------------
    // PÁGINA A4: PESTAÑA SISTEMA (COMUNICADOS, CONTROLES Y ACTUALIZACIONES OTA)
    // -------------------------------------------------------------------------
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildChapterTitle('MODULO 4: SISTEMA - COMUNICADOS, CONTROLES GENERALES Y ACTUALIZACIONES OTA'),
              pw.SizedBox(height: 6),

              _buildCalloutItem(
                number: '1',
                title: 'PUBLICAR COMUNICADO OFICIAL Y TELEFONOS',
                action: 'Emite avisos comunitarios sin sonar la sirena (cortes de luz, reuniones de pasaje).',
                instruction: 'Configura la patrulla comunitaria (1414) y el WhatsApp que recibe las fotos (+56921839786).',
                badgeColor: PdfColors.indigo900,
              ),
              _buildCalloutItem(
                number: '2',
                title: 'CONTROL GENERAL DE ALARMA COMUNITARIA',
                action: 'Herramientas de mando maestro.',
                instruction: '[Disparar Alarma de Prueba]: Activa simulacro. [Cancelar Alarma Activa General]: Silencia cualquier alarma en la villa.',
                badgeColor: PdfColors.orange900,
              ),
              _buildCalloutItem(
                number: '3',
                title: 'ACTUALIZACIONES REMOTAS OTA (SIN CODIGOS QR)',
                action: 'Actualiza la app de todos los vecinos en 1 toque.',
                instruction: 'Pega el enlace de descarga APK y version (ej: 1.0.3) y pulsa "Notificar Actualizacion". A cada vecino le saldra el boton verde para actualizar.',
                badgeColor: PdfColors.green900,
              ),
              _buildCalloutItem(
                number: '4',
                title: 'RESPALDO JSON Y MANTENIMIENTO',
                action: 'Copia de seguridad y optimizacion de base de datos.',
                instruction: '[Exportar Respaldo JSON] guarda todo en tu equipo. [Borrar > 30 dias] limpia reportes viejos para mantener la app veloz.',
                badgeColor: PdfColors.grey900,
              ),

              pw.SizedBox(height: 8),

              // 4 Capturas en Cuadrícula 2x2 Grandes y Claras
              pw.Column(
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      if (imgSystemTop != null)
                        pw.Column(
                          children: [
                            _buildScreenshotFrame(imgSystemTop, height: 180),
                            pw.SizedBox(height: 2),
                            pw.Text('Fig. A6: Comunicados y Telefonos.', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                          ],
                        ),
                      if (imgSystemTop != null && imgSystemMiddle != null) pw.SizedBox(width: 16),
                      if (imgSystemMiddle != null)
                        pw.Column(
                          children: [
                            _buildScreenshotFrame(imgSystemMiddle, height: 180),
                            pw.SizedBox(height: 2),
                            pw.Text('Fig. A7: Manuales y Controles.', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                          ],
                        ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      if (imgSystemOta != null)
                        pw.Column(
                          children: [
                            _buildScreenshotFrame(imgSystemOta, height: 180),
                            pw.SizedBox(height: 2),
                            pw.Text('Fig. A8: Actualizaciones OTA.', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                          ],
                        ),
                      if (imgSystemOta != null && imgSystemBottom != null) pw.SizedBox(width: 16),
                      if (imgSystemBottom != null)
                        pw.Column(
                          children: [
                            _buildScreenshotFrame(imgSystemBottom, height: 180),
                            pw.SizedBox(height: 2),
                            pw.Text('Fig. A9: Respaldo y Mantenimiento.', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                          ],
                        ),
                    ],
                  ),
                ],
              ),

              pw.Spacer(),
              _buildPageFooter('Panel Administrador - Villa Escuadron Galilea, Coronel (Pagina 4 de 4)'),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Manual_Administrador_Villa_Escuadron_Galilea.pdf',
    );
  }

  // ===========================================================================
  // WIDGETS Y COMPONENTES REUTILIZABLES DE MAQUETACIÓN PDF
  // ===========================================================================

  static pw.Widget _buildHeader({
    required String title,
    required String subtitle,
    required String headerColorHex,
    required String badgeText,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex(headerColorHex),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  subtitle,
                  style: const pw.TextStyle(color: PdfColors.amber200, fontSize: 7.5),
                ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(
              color: PdfColors.red700,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              badgeText,
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildChapterTitle(String title) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
      ),
    );
  }

  static pw.Widget _buildScreenshotFrame(Uint8List imageBytes, {double height = 370, double? width}) {
    return pw.Container(
      height: height,
      width: width,
      padding: const pw.EdgeInsets.all(3),
      decoration: pw.BoxDecoration(
        color: PdfColors.black,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.blueGrey400, width: 1.5),
      ),
      child: pw.ClipRRect(
        horizontalRadius: 6,
        verticalRadius: 6,
        child: pw.Image(
          pw.MemoryImage(imageBytes),
          fit: pw.BoxFit.contain,
        ),
      ),
    );
  }

  static pw.Widget _buildCalloutItem({
    required String number,
    required String title,
    required String action,
    required String instruction,
    String? tip,
    PdfColor badgeColor = PdfColors.indigo900,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 15,
            height: 15,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: badgeColor,
              shape: pw.BoxShape.circle,
            ),
            child: pw.Text(
              number,
              style: pw.TextStyle(color: PdfColors.white, fontSize: 8.5, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: badgeColor),
                ),
                pw.Text('Accion: $action', style: const pw.TextStyle(fontSize: 7.2, color: PdfColors.grey900)),
                pw.Text('Que hacer: $instruction', style: const pw.TextStyle(fontSize: 7.2, color: PdfColors.blueGrey900)),
                if (tip != null) ...[
                  pw.Text('Consejo: $tip', style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic, color: PdfColors.amber900)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPageFooter(String text) {
    return pw.Center(
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic, color: PdfColors.grey600),
      ),
    );
  }
}
