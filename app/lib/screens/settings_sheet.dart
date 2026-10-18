import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/neighborhood_locations.dart';
import '../services/alarm_player_service.dart';
import '../services/alarm_sync_service.dart';
import '../services/native_alert_service.dart';
import '../theme/app_theme.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  bool _isTestingSiren = false;
  bool _isIgnoringBattery = false;
  String _selectedSirenType = 'ROBO'; // 'ROBO', 'INCENDIO', 'MÉDICO', 'GENERAL'

  @override
  void initState() {
    super.initState();
    final service = AlarmSyncService();
    _nameController = TextEditingController(text: service.neighborName);
    _urlController = TextEditingController(text: service.serverUrl);
    _checkBattery();
  }

  Future<void> _checkBattery() async {
    final status = await NativeAlertService.isIgnoringBatteryOptimizations();
    if (mounted) setState(() => _isIgnoringBattery = status);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    if (_isTestingSiren) {
      AlarmPlayerService().stopAlarm();
    }
    super.dispose();
  }

  void _toggleSirenTest() async {
    if (_isTestingSiren) {
      await AlarmPlayerService().stopAlarm();
      setState(() => _isTestingSiren = false);
    } else {
      setState(() => _isTestingSiren = true);
      await AlarmPlayerService().startAlarm(_selectedSirenType);
    }
  }

  void _requestBatteryPermission() async {
    await NativeAlertService.requestIgnoreBatteryOptimizations();
    await Future.delayed(const Duration(seconds: 1));
    _checkBattery();
  }

  Future<void> _openEditProfileDialog() async {
    final service = AlarmSyncService();
    final attempts = await service.getEditProfileAttempts();
    final firstCtrl = TextEditingController(text: service.firstName);
    final l1Ctrl = TextEditingController(text: service.lastName1);
    final l2Ctrl = TextEditingController(text: service.lastName2);

    final streets = NeighborhoodLocations.getStreetsForSector('Villa Escuadrón Galilea');
    final galileaNumbers = NeighborhoodLocations.getGalileaHouseNumbers();
    String selectedStreet = streets.contains(service.address) ? service.address : streets.first;
    String selectedHouse = galileaNumbers.contains(service.houseNumber) ? service.houseNumber : galileaNumbers.first;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isLocked = attempts >= 3;
          final remaining = 3 - attempts;
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  isLocked ? Icons.lock : Icons.manage_accounts,
                  color: isLocked ? Colors.red : AppColors.steelBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isLocked ? 'Datos Bloqueados' : 'Corregir Mis Datos',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isLocked
                          ? (isDark ? const Color(0xFF450A0A) : Colors.red.shade50)
                          : (isDark ? const Color(0xFF1E293B) : Colors.blue.shade50),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isLocked ? Colors.red.shade400 : Colors.blue.shade200,
                      ),
                    ),
                    child: Text(
                      isLocked
                          ? '🔒 Límite de 3 intentos alcanzado.\n\nPara evitar suplantaciones o cuentas duplicadas, debes solicitar autorización a la Administración o pedirle al Administrador que modifique tus datos desde su panel.'
                          : 'ℹ️ Tienes $remaining intento(s) restante(s) para corregir tu nombre o dirección (Intento ${attempts + 1} de 3).\n\nSelecciona las calles y números reales de la villa.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isLocked
                            ? (isDark ? Colors.red.shade200 : Colors.red.shade900)
                            : (isDark ? const Color(0xFF93C5FD) : AppColors.brandNavy),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: firstCtrl,
                    enabled: !isLocked,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nombre(s) *',
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: l1Ctrl,
                    enabled: !isLocked,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Primer Apellido (Paterno) *',
                      prefixIcon: Icon(Icons.badge),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: l2Ctrl,
                    enabled: !isLocked,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Segundo Apellido (Materno) *',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedStreet,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Pasaje / Calle en Villa Galilea *',
                      prefixIcon: Icon(Icons.add_road),
                    ),
                    items: streets.map((st) {
                      return DropdownMenuItem(value: st, child: Text(st, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)));
                    }).toList(),
                    onChanged: isLocked ? null : (v) {
                      if (v != null) setDialogState(() => selectedStreet = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: galileaNumbers.contains(selectedHouse) ? selectedHouse : galileaNumbers.first,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Número de Casa *',
                      prefixIcon: Icon(Icons.home),
                    ),
                    items: galileaNumbers.map((n) {
                      return DropdownMenuItem(value: n, child: Text('#$n', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)));
                    }).toList(),
                    onChanged: isLocked ? null : (v) {
                      if (v != null) setDialogState(() => selectedHouse = v);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cerrar'),
              ),
              if (isLocked)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    Navigator.pop(dialogCtx);
                    final wpNumber = await service.getAdminWhatsApp();
                    final cleanPhone = wpNumber.replaceAll(RegExp(r'[^0-9]'), '');
                    final msg = Uri.encodeComponent(
                      'Hola Administrador, soy ${service.fullName} de ${service.fullAddress}. He agotado mis 3 intentos de corrección de datos en la app Alerta Vecinal y solicito que me habilites nuevos intentos o me ayudes a modificar mi dirección.',
                    );
                    final uri = Uri.parse('https://wa.me/$cleanPhone?text=$msg');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.chat, size: 16),
                  label: const Text('Pedir Permiso al Admin'),
                )
              else
                ElevatedButton(
                  onPressed: () async {
                    final fName = firstCtrl.text.trim();
                    final l1 = l1Ctrl.text.trim();
                    final l2 = l2Ctrl.text.trim();

                    final errFn = NeighborhoodLocations.validateHumanName(fName, 'Nombre');
                    if (errFn != null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(errFn)));
                      return;
                    }

                    final errL1 = NeighborhoodLocations.validateHumanName(l1, 'Primer apellido');
                    if (errL1 != null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(errL1)));
                      return;
                    }

                    final errL2 = NeighborhoodLocations.validateHumanName(l2, 'Segundo apellido');
                    if (errL2 != null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(errL2)));
                      return;
                    }

                    final (ok, msg) = await service.updateNeighborProfile(
                      firstName: fName,
                      lastName1: l1,
                      lastName2: l2,
                      address: selectedStreet,
                      houseNumber: selectedHouse,
                    );

                    if (!ctx.mounted) return;
                    if (ok) {
                      Navigator.pop(dialogCtx);
                      setState(() {
                        _nameController.text = service.neighborName;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppColors.sageGreen,
                          content: Text(msg),
                        ),
                      );
                    } else {
                      showDialog(
                        context: ctx,
                        builder: (errCtx) => AlertDialog(
                          title: const Row(
                            children: [
                              Icon(Icons.warning_amber, color: Colors.orange),
                              SizedBox(width: 8),
                              Text('No se pudo guardar'),
                            ],
                          ),
                          content: Text(msg),
                          actions: [
                            ElevatedButton(
                              onPressed: () => Navigator.pop(errCtx),
                              child: const Text('Entendido'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                  child: const Text('Guardar Corrección'),
                ),
            ],
          );
        },
      ),
    );
  }

  void _save() async {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();

    if (name.isEmpty || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor ingresa un nombre y una dirección válida.')),
      );
      return;
    }

    await AlarmSyncService().updateConfig(newUrl: url, newName: name);
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.sageGreen,
          content: Text('Configuración guardada y reconectando...', style: TextStyle(color: Colors.white)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = AppColors.textPrimaryOf(context);
    final secondaryTextColor = AppColors.textSecondaryOf(context);
    final fieldFillColor = AppColors.fieldFillOf(context);
    final fieldBorderColor = AppColors.fieldBorderOf(context);

    // Margen seguro considerando barra inferior de Android (3 botones ||| 🔲 <) y teclado
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomSystemBar = MediaQuery.of(context).padding.bottom;
    final totalBottomPadding = bottomInset + bottomSystemBar + 32.0;

    return SafeArea(
      bottom: true,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: totalBottomPadding,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Configuración del Dispositivo',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: primaryTextColor,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: secondaryTextColor),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // OPCIÓN 1: Tema Blanco / Negro (Modo Oscuro)
              ValueListenableBuilder<ThemeMode>(
                valueListenable: ThemeService().themeModeNotifier,
                builder: (context, themeMode, _) {
                  final isCurrentlyDark = themeMode == ThemeMode.dark;
                  return Container(
                    decoration: BoxDecoration(
                      color: fieldFillColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: fieldBorderColor),
                    ),
                    child: SwitchListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      secondary: Icon(
                        isCurrentlyDark ? Icons.dark_mode : Icons.light_mode,
                        color: isCurrentlyDark ? const Color(0xFFFACC15) : AppColors.steelBlue,
                      ),
                      title: Text(
                        'Modo de Pantalla',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: primaryTextColor),
                      ),
                      subtitle: Text(
                        isCurrentlyDark ? 'Tema Oscuro (Fondo negro de noche)' : 'Tema Claro (Fondo blanco de día)',
                        style: TextStyle(fontSize: 11, color: secondaryTextColor),
                      ),
                      value: isCurrentlyDark,
                      onChanged: (val) async {
                        await ThemeService().setDarkMode(val);
                        if (mounted) setState(() {});
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // OPCIÓN 2: Corregir Mis Datos / Dirección de Vivienda
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _openEditProfileDialog,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: fieldFillColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: fieldBorderColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.steelBlue.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.manage_accounts, color: AppColors.steelBlue, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Corregir Mis Datos / Dirección',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: primaryTextColor),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Modificar nombre, calle o número de casa (máx. 3 intentos)',
                              style: TextStyle(fontSize: 11, color: secondaryTextColor),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, size: 14, color: secondaryTextColor),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Identificador de vecino
              Text(
                'Identificador de tu Vivienda / Nombre',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: secondaryTextColor),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                style: TextStyle(color: primaryTextColor),
                decoration: InputDecoration(
                  hintText: 'Ej. Casa 14 - Familia Soto',
                  hintStyle: TextStyle(color: secondaryTextColor.withValues(alpha: 0.6)),
                  filled: true,
                  fillColor: fieldFillColor,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: fieldBorderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: fieldBorderColor),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Dirección del servidor
              Text(
                'Dirección del Servidor (WebSocket)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: secondaryTextColor),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _urlController,
                style: TextStyle(color: primaryTextColor),
                decoration: InputDecoration(
                  hintText: 'ws://192.168.1.100:7866 o wss://tu-dominio.com',
                  hintStyle: TextStyle(color: secondaryTextColor.withValues(alpha: 0.6)),
                  filled: true,
                  fillColor: fieldFillColor,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: fieldBorderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: fieldBorderColor),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Tarjeta de Permiso de Batería (Contraste verificado para modo claro y oscuro)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _isIgnoringBattery
                      ? (isDark ? const Color(0xFF064E3B) : AppColors.sageGreenLight)
                      : (isDark ? const Color(0xFF33230A) : AppColors.amberWarningLight),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isIgnoringBattery
                        ? (isDark ? Colors.green.shade600 : AppColors.sageGreen)
                        : (isDark ? Colors.amber.shade700 : AppColors.amberWarning),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isIgnoringBattery ? Icons.check_circle_outline : Icons.battery_alert_outlined,
                      color: _isIgnoringBattery
                          ? (isDark ? Colors.green.shade300 : AppColors.sageGreen)
                          : (isDark ? Colors.amber.shade300 : AppColors.amberWarning),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isIgnoringBattery
                                ? 'Segundo Plano Ilimitado Activo'
                                : 'Optimización de Batería Pendiente',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _isIgnoringBattery
                                  ? (isDark ? Colors.green.shade200 : AppColors.sageGreen)
                                  : (isDark ? Colors.amber.shade200 : AppColors.textPrimary),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isIgnoringBattery
                                ? 'Tu teléfono recibirá la alarma incluso si está bloqueado.'
                                : 'Requerido para que la alarma suene con pantalla apagada.',
                            style: TextStyle(
                              fontSize: 11,
                              color: _isIgnoringBattery
                                  ? (isDark ? Colors.green.shade300 : AppColors.textSecondary)
                                  : (isDark ? Colors.amber.shade300 : AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_isIgnoringBattery)
                      TextButton(
                        onPressed: _requestBatteryPermission,
                        child: Text(
                          'PERMITIR',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.amber.shade200 : AppColors.brandNavy,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Selector de Tono de Alarma para probar
              Text(
                'Tono de Sirena para Probar',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: secondaryTextColor),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('🕵️ Robo / Intruso', style: TextStyle(fontSize: 12)),
                      selected: _selectedSirenType == 'ROBO',
                      onSelected: (s) => setState(() => _selectedSirenType = 'ROBO'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('🔥 Incendio', style: TextStyle(fontSize: 12)),
                      selected: _selectedSirenType == 'INCENDIO',
                      onSelected: (s) => setState(() => _selectedSirenType = 'INCENDIO'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('🚑 Médica', style: TextStyle(fontSize: 12)),
                      selected: _selectedSirenType == 'MÉDICO',
                      onSelected: (s) => setState(() => _selectedSirenType = 'MÉDICO'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('🚨 General', style: TextStyle(fontSize: 12)),
                      selected: _selectedSirenType == 'GENERAL',
                      onSelected: (s) => setState(() => _selectedSirenType = 'GENERAL'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Botón de Prueba de Sirena
              OutlinedButton.icon(
                onPressed: _toggleSirenTest,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(
                    color: _isTestingSiren
                        ? AppColors.alertCrimson
                        : (isDark ? const Color(0xFF475569) : AppColors.borderMedium),
                    width: 1.5,
                  ),
                  foregroundColor: _isTestingSiren
                      ? AppColors.alertCrimson
                      : (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(_isTestingSiren ? Icons.stop_circle_outlined : Icons.volume_up_outlined),
                label: Text(
                  _isTestingSiren ? 'Detener Sirena de Prueba' : 'Probar Tono: $_selectedSirenType',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 20),

              // Botón Guardar (con margen inferior seguro para botones de navegación Android)
              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Guardar y Reconectar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
