import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/neighborhood_locations.dart';
import '../services/alarm_sync_service.dart';
import '../services/biometric_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

class RegisterScreen extends StatefulWidget {
  final bool isPreview;
  const RegisterScreen({super.key, this.isPreview = false});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _restoreFormKey = GlobalKey<FormState>();
  final _service = AlarmSyncService();

  // Pestaña activa: 0 = Nueva Vivienda, 1 = Ya Estoy Registrado
  int _activeTab = 0;

  // Ubicación jerárquica
  String _selectedRegion = NeighborhoodLocations.defaultRegion;
  String _selectedComuna = NeighborhoodLocations.defaultComuna;
  String _selectedSector = NeighborhoodLocations.defaultSector;
  String _selectedStreet = NeighborhoodLocations.defaultStreet;
  String _selectedHouseNumber = NeighborhoodLocations.defaultHouseNumber;
  String _selectedInterior = 'Casa Principal';

  // Controladores Formulario de Registro
  final _firstNameCtrl = TextEditingController();
  final _lastName1Ctrl = TextEditingController();
  final _lastName2Ctrl = TextEditingController();
  final _customSectorCtrl = TextEditingController();
  final _customStreetCtrl = TextEditingController();
  final _customHouseCtrl = TextEditingController(text: NeighborhoodLocations.defaultHouseNumber);
  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  // Controladores Formulario de Recuperación
  bool _restoreByPhone = true;
  final _restorePhoneCtrl = TextEditingController();
  String _restoreStreet = NeighborhoodLocations.defaultStreet;
  final _restoreHouseCtrl = TextEditingController(text: NeighborhoodLocations.defaultHouseNumber);
  final _restorePinCtrl = TextEditingController();

  bool _isSaving = false;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastName1Ctrl.dispose();
    _lastName2Ctrl.dispose();
    _customSectorCtrl.dispose();
    _customStreetCtrl.dispose();
    _customHouseCtrl.dispose();
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    _restorePhoneCtrl.dispose();
    _restoreHouseCtrl.dispose();
    _restorePinCtrl.dispose();
    super.dispose();
  }

  String _getEffectiveSector() {
    if (_selectedSector == NeighborhoodLocations.customSectorOption) {
      return _customSectorCtrl.text.trim();
    }
    return _selectedSector;
  }

  String _getEffectiveStreet() {
    if (_selectedStreet == NeighborhoodLocations.customStreetOption) {
      return _customStreetCtrl.text.trim();
    }
    return _selectedStreet;
  }

  String _getEffectiveHouseNumber() {
    if (_selectedSector == 'Villa Escuadrón Galilea') {
      return _selectedHouseNumber;
    }
    return _customHouseCtrl.text.trim();
  }

  String _buildFullHouseNumber() {
    final house = _getEffectiveHouseNumber();
    if (_selectedInterior == 'Casa Principal' || _selectedInterior.isEmpty) {
      return house;
    }
    return '$house ($_selectedInterior)';
  }

  Future<void> _submitNeighbor() async {
    if (!_formKey.currentState!.validate()) return;

    if (widget.isPreview) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.sageGreen,
          duration: Duration(seconds: 4),
          content: Text(
            '✓ [VISTA PREVIA]: Formulario completamente válido con datos reales de Villa Galilea. En modo real, se vincularía esta vivienda.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
      return;
    }

    final effectiveStreet = _getEffectiveStreet();
    final fullHouseNum = _buildFullHouseNumber();
    final cleanPhone = _phoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');

    setState(() => _isSaving = true);
    try {
      // 1. Comprobar si ya existe una cuenta previa para esta vivienda o persona
      final existing = await _service.findExistingNeighborMatch(
        phone: cleanPhone,
        address: effectiveStreet,
        houseNumber: fullHouseNum,
        firstName: _firstNameCtrl.text.trim(),
        lastName1: _lastName1Ctrl.text.trim(),
      );

      if (existing != null) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        await _showSmartRecoveryDialog(existing);
        return;
      }

      // 2. Comprobar duplicados estrictos
      final dupCheck = await _service.checkDuplicateNeighbor(
        firstName: _firstNameCtrl.text.trim(),
        lastName1: _lastName1Ctrl.text.trim(),
        lastName2: _lastName2Ctrl.text.trim(),
        address: effectiveStreet,
        houseNumber: fullHouseNum,
        phone: cleanPhone,
      );

      if (dupCheck.$1) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        final dupMsg = dupCheck.$2 ?? '';
        if (dupMsg.startsWith('LIMIT_REACHED::')) {
          final parts = dupMsg.split('::');
          final cCount = int.tryParse(parts.length > 1 ? parts[1] : '3') ?? 3;
          final cLimit = int.tryParse(parts.length > 2 ? parts[2] : '3') ?? 3;
          await _showHouseLimitReachedDialog(cCount, cLimit, effectiveStreet, fullHouseNum);
          return;
        }

        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 26),
                SizedBox(width: 8),
                Text('Registro Existente'),
              ],
            ),
            content: Text(dupMsg.isNotEmpty ? dupMsg : 'Ya existe un residente similar registrado.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _activeTab = 1);
                },
                child: const Text('Recuperar mi Cuenta'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        return;
      }

      // 3. Registrar vecino con datos verificados
      await _service.registerNeighbor(
        firstName: _firstNameCtrl.text.trim(),
        lastName1: _lastName1Ctrl.text.trim(),
        lastName2: _lastName2Ctrl.text.trim(),
        region: _selectedRegion,
        comuna: _selectedComuna,
        sector: _getEffectiveSector(),
        address: effectiveStreet,
        houseNumber: fullHouseNum,
        phone: cleanPhone,
        pin: _pinCtrl.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.sageGreen,
          content: Text(
            '¡Registro completado! Tu vivienda está vinculada.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text('Error al registrar: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _submitRestoreAccount() async {
    if (!_restoreFormKey.currentState!.validate()) return;

    if (widget.isPreview) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.sageGreen,
          duration: Duration(seconds: 4),
          content: Text(
            '✓ [VISTA PREVIA]: Validación de restauración exitosa. En modo normal, se recuperaría el acceso con tu PIN.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final (ok, msg) = await _service.restoreNeighborAccount(
        phone: _restoreByPhone ? _restorePhoneCtrl.text.trim() : null,
        address: !_restoreByPhone ? _restoreStreet : null,
        houseNumber: !_restoreByPhone ? _restoreHouseCtrl.text.trim() : null,
        enteredPin: _restorePinCtrl.text.trim(),
      );

      if (!mounted) return;
      setState(() => _isSaving = false);

      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.sageGreen,
            content: Text(
              msg,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.lock_clock, color: Colors.red),
                SizedBox(width: 8),
                Text('No se pudo restaurar'),
              ],
            ),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Volver a Intentar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red.shade800, content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _showHouseLimitReachedDialog(int currentCount, int limit, String address, String houseNumber) async {
    final rawAdminPhone = await _service.getAdminWhatsApp();
    final cleanAdminPhone = rawAdminPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final effectiveAdminPhone = cleanAdminPhone.isNotEmpty ? cleanAdminPhone : '56921839786';
    final applicantName = '${_firstNameCtrl.text.trim()} ${_lastName1Ctrl.text.trim()}'.trim();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.devices, color: Colors.orange, size: 26),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Límite de Dispositivos por Casa',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🏠 $address #$houseNumber',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.brandNavy),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Capacidad utilizada: $currentCount de $limit teléfonos registrados.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'El plan comunitario estándar cubre hasta 3 teléfonos por vivienda (3 familiares incluidos en los \$30.000).\n\n'
                'Para habilitar un 4° teléfono adicional (o más familiares para tu hogar), se debe abonar la tarifa única de \$5.000 CLP.\n\n'
                'Una vez cancelado el monto, el Administrador habilitará el nuevo cupo en el sistema y podrás registrar este teléfono al instante.',
                style: TextStyle(fontSize: 12.5, height: 1.35),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final msg = 'Hola Administrador, necesito habilitar un cupo adicional (+1 teléfono por \$5.000 CLP) para mi vivienda en $address #$houseNumber a nombre de $applicantName.';
              final uri = Uri.parse('https://wa.me/$effectiveAdminPhone?text=${Uri.encodeComponent(msg)}');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.chat, size: 16),
            label: const Text('Contactar Soporte WhatsApp (\$5.000)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Future<void> _showSmartRecoveryDialog(Map<String, dynamic> existing) async {
    final name = existing['nombreCompleto'] ?? existing['nombre'] ?? 'Vecino';
    final addr = existing['direccionCompleta'] ?? '${existing['direccion']} #${existing['numeroCasa']}';
    final pinDialogCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.home_work, color: AppColors.brandNavy, size: 26),
              SizedBox(width: 8),
              Expanded(child: Text('¡Vivienda ya Registrada!')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ya existe un perfil activo para esta vivienda a nombre de:\n',
                  style: const TextStyle(fontSize: 13),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '👤 $name',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.brandNavy),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '🏠 $addr',
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Si desinstalaste la aplicación o cambiaste de equipo celular, puedes restaurar tu cuenta ingresando tu PIN de seguridad de 4 dígitos:',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pinDialogCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'PIN de 4 dígitos',
                    prefixIcon: Icon(Icons.password),
                    hintText: 'Ej. 1234',
                  ),
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
                final pin = pinDialogCtrl.text.trim();
                if (pin.length != 4) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Ingresa el PIN de 4 dígitos')),
                  );
                  return;
                }
                Navigator.pop(ctx);
                setState(() => _isSaving = true);
                final (ok, msg) = await _service.restoreNeighborAccount(
                  address: existing['direccion'] ?? existing['calle'],
                  houseNumber: existing['numeroCasa'] ?? existing['casa'],
                  enteredPin: pin,
                );
                if (!mounted) return;
                setState(() => _isSaving = false);
                if (ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: AppColors.sageGreen, content: Text(msg)),
                  );
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: Colors.red.shade800, content: Text(msg)),
                  );
                }
              },
              child: const Text('Restaurar Cuenta'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAdminAccess() async {
    if (widget.isPreview) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Estás en la vista previa del registro. Usa el botón superior para cerrar.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final hasAdmin = await _service.hasAdminInFirebase();
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (hasAdmin) {
      final canBio = await BiometricService.canAuthenticate();
      if (canBio) {
        final bioOk = await BiometricService.authenticate(
          reason: 'Confirma tu huella dactilar para acceder como Administrador',
        );
        if (bioOk) {
          final valid = await _service.loginAsAdmin('', biometricOverride: true);
          if (valid && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: AppColors.brandNavy,
                content: Text('¡Autenticado con huella! Modo Administrador activo.'),
              ),
            );
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            );
            return;
          }
        }
      }

      final pinCtrl = TextEditingController();
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.shield, color: AppColors.brandNavy),
              SizedBox(width: 8),
              Text('Acceso Administrador'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'El Administrador General ya ha sido configurado en el sistema.\nIngresa el PIN de seguridad o usa tu huella para acceder:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Center(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final bioOk = await BiometricService.authenticate(
                      reason: 'Confirma tu huella dactilar',
                    );
                    if (bioOk) {
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx, true);
                      final valid = await _service.loginAsAdmin('', biometricOverride: true);
                      if (valid && mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const HomeScreen()),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.fingerprint, color: AppColors.brandNavy),
                  label: const Text('Usar Huella Dactilar'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'PIN de Administrador',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Entrar'),
            ),
          ],
        ),
      );

      if (ok == true && pinCtrl.text.isNotEmpty) {
        setState(() => _isSaving = true);
        final valid = await _service.loginAsAdmin(pinCtrl.text.trim());
        if (!mounted) return;
        setState(() => _isSaving = false);

        if (valid) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppColors.brandNavy,
              content: Text('¡Modo Administrador activado!'),
            ),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade800,
              content: const Text('PIN de Administrador incorrecto.'),
            ),
          );
        }
      }
    } else {
      // Crear administrador por primera vez con ubicación de la villa
      final adminFnCtrl = TextEditingController();
      final adminL1Ctrl = TextEditingController();
      final adminL2Ctrl = TextEditingController();
      String adminStreet = NeighborhoodLocations.defaultStreet;
      String adminHouse = NeighborhoodLocations.defaultHouseNumber;
      final adminPhoneCtrl = TextEditingController();
      final adminPinCtrl = TextEditingController();

      final created = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDlgState) => AlertDialog(
            title: const Text('Crear Administrador Único'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No existe un Administrador registrado. Como primer usuario administrador, ingresa tus datos en Villa Galilea y crea tu PIN de acceso exclusivo:',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: adminStreet,
                    decoration: const InputDecoration(labelText: 'Calle / Pasaje en Villa Galilea *'),
                    items: NeighborhoodLocations.getStreetsForSector('Villa Escuadrón Galilea')
                        .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (v) => setDlgState(() => adminStreet = v!),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: adminHouse,
                    decoration: const InputDecoration(labelText: 'Número de Casa *'),
                    items: NeighborhoodLocations.getGalileaHouseNumbers()
                        .map((n) => DropdownMenuItem(value: n, child: Text(n, style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (v) => setDlgState(() => adminHouse = v!),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: adminFnCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre *'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: adminL1Ctrl,
                    decoration: const InputDecoration(labelText: 'Primer Apellido *'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: adminL2Ctrl,
                    decoration: const InputDecoration(labelText: 'Segundo Apellido *'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: adminPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono Móvil (9 dígitos) *',
                      prefixText: '+56 ',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: adminPinCtrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Crea tu PIN de Administrador (4 a 6 dígitos)',
                      prefixIcon: Icon(Icons.password),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  final fn = adminFnCtrl.text.trim();
                  final l1 = adminL1Ctrl.text.trim();
                  final pin = adminPinCtrl.text.trim();
                  if (fn.isEmpty || l1.isEmpty || pin.length < 4) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Por favor completa los datos y crea un PIN de mínimo 4 dígitos.'),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('Crear Administrador'),
              ),
            ],
          ),
        ),
      );

      if (created == true) {
        setState(() => _isSaving = true);
        await _service.registerAdmin(
          firstName: adminFnCtrl.text.trim(),
          lastName1: adminL1Ctrl.text.trim(),
          lastName2: adminL2Ctrl.text.trim(),
          region: NeighborhoodLocations.defaultRegion,
          comuna: NeighborhoodLocations.defaultComuna,
          sector: NeighborhoodLocations.defaultSector,
          address: adminStreet,
          houseNumber: adminHouse,
          phone: adminPhoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
          pin: adminPinCtrl.text.trim(),
        );
        if (!mounted) return;
        setState(() => _isSaving = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.brandNavy,
            content: Text('¡Administrador registrado exitosamente!'),
          ),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final comunas = NeighborhoodLocations.getComunasForRegion(_selectedRegion);
    final sectores = NeighborhoodLocations.getSectoresForComuna(_selectedComuna);
    final streets = NeighborhoodLocations.getStreetsForSector(_selectedSector);
    final galileaNumbers = NeighborhoodLocations.getGalileaHouseNumbers();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: widget.isPreview
          ? AppBar(
              title: const Text('Vista Previa: Registro de Vecinos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cerrar Vista Previa',
                onPressed: () => Navigator.pop(context),
              ),
              backgroundColor: isDark ? const Color(0xFF1E293B) : AppColors.brandNavy,
              foregroundColor: Colors.white,
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 40 + MediaQuery.of(context).padding.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.isPreview) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF78350F) : Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.amber.shade600 : Colors.amber.shade700,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.visibility, color: isDark ? Colors.amber.shade200 : Colors.amber.shade900),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MODO VISTA PREVIA ADMINISTRADOR',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.amber.shade100 : Colors.amber.shade900,
                              ),
                            ),
                            Text(
                              'Así ven la pantalla los vecinos al instalar la app. Los selectores y validaciones son 100% interactivos y no alteran tus datos.',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.amber.shade200 : Colors.brown.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 6),

              // Logo y Título
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/icon.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.shield,
                        size: 60,
                        color: AppColors.brandNavyOf(context),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'CENTINELA URBANO',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: AppColors.brandNavyOf(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Villa Escuadrón Galilea • Coronel',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),

              const SizedBox(height: 18),

              // Selector de Pestaña: Nueva Vivienda vs Ya Estoy Registrado
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _activeTab = 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _activeTab == 0
                                ? (isDark ? const Color(0xFF2563EB) : AppColors.brandNavy)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            '📝 Nueva Vivienda',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: _activeTab == 0 ? Colors.white : AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _activeTab = 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _activeTab == 1
                                ? (isDark ? const Color(0xFF2563EB) : AppColors.brandNavy)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            '🔑 Ya Estoy Registrado',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: _activeTab == 1 ? Colors.white : AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // CONTENIDO DE LA PESTAÑA ACTIVA
              if (_activeTab == 0) ...[
                // TARJETA DE REGISTRO NUEVO CON SELECTS CASCADA
                Card(
                  elevation: isDark ? 0 : 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: isDark ? const BorderSide(color: AppColors.darkBorder, width: 1) : BorderSide.none,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.map_outlined, color: AppColors.steelBlue, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Ubicación Oficial en la Villa',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.brandNavyOf(context),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Selecciona tu calle y número real para que tus vecinos identifiquen tu hogar ante una emergencia.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                          ),
                          const SizedBox(height: 14),

                          // 1. Región
                          DropdownButtonFormField<String>(
                            value: _selectedRegion,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '1. Región *',
                              prefixIcon: Icon(Icons.public),
                            ),
                            items: NeighborhoodLocations.regions.map((r) {
                              return DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13)));
                            }).toList(),
                            onChanged: (val) {
                              if (val == null) return;
                              setState(() {
                                _selectedRegion = val;
                                final newComunas = NeighborhoodLocations.getComunasForRegion(val);
                                _selectedComuna = newComunas.first;
                                final newSectores = NeighborhoodLocations.getSectoresForComuna(_selectedComuna);
                                _selectedSector = newSectores.first;
                                final newStreets = NeighborhoodLocations.getStreetsForSector(_selectedSector);
                                _selectedStreet = newStreets.first;
                              });
                            },
                          ),
                          const SizedBox(height: 12),

                          // 2. Comuna
                          DropdownButtonFormField<String>(
                            value: comunas.contains(_selectedComuna) ? _selectedComuna : comunas.first,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '2. Comuna *',
                              prefixIcon: Icon(Icons.location_city),
                            ),
                            items: comunas.map((c) {
                              return DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13)));
                            }).toList(),
                            onChanged: (val) {
                              if (val == null) return;
                              setState(() {
                                _selectedComuna = val;
                                final newSectores = NeighborhoodLocations.getSectoresForComuna(val);
                                _selectedSector = newSectores.first;
                                final newStreets = NeighborhoodLocations.getStreetsForSector(_selectedSector);
                                _selectedStreet = newStreets.first;
                              });
                            },
                          ),
                          const SizedBox(height: 12),

                          // 3. Sector
                          DropdownButtonFormField<String>(
                            value: sectores.contains(_selectedSector) ? _selectedSector : sectores.first,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '3. Sector / Villa *',
                              prefixIcon: Icon(Icons.holiday_village_outlined),
                            ),
                            items: sectores.map((s) {
                              return DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)));
                            }).toList(),
                            onChanged: (val) {
                              if (val == null) return;
                              setState(() {
                                _selectedSector = val;
                                final newStreets = NeighborhoodLocations.getStreetsForSector(val);
                                _selectedStreet = newStreets.first;
                              });
                            },
                          ),
                          if (_selectedSector == NeighborhoodLocations.customSectorOption) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _customSectorCtrl,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Nombre de tu Villa o Sector *',
                                hintText: 'Ej. Villa Los Boldos',
                                prefixIcon: Icon(Icons.holiday_village),
                              ),
                              validator: NeighborhoodLocations.validateStreetName,
                            ),
                          ],
                          const SizedBox(height: 12),

                          // 4. Calle / Pasaje (SELECT REAL)
                          DropdownButtonFormField<String>(
                            value: streets.contains(_selectedStreet) ? _selectedStreet : streets.first,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '4. Pasaje / Calle Real *',
                              prefixIcon: Icon(Icons.add_road),
                            ),
                            items: streets.map((st) {
                              return DropdownMenuItem(value: st, child: Text(st, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedStreet = val);
                            },
                          ),
                          if (_selectedStreet == NeighborhoodLocations.customStreetOption) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _customStreetCtrl,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Nombre de tu Pasaje o Calle *',
                                hintText: 'Ej. Pasaje Los Lingues',
                                prefixIcon: Icon(Icons.edit_road),
                              ),
                              validator: NeighborhoodLocations.validateStreetName,
                            ),
                          ],
                          const SizedBox(height: 12),

                          // 5. Número de Casa (SELECT REAL EN GALILEA / INGRESO NUMÉRICO VALIDADO EN OTROS)
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: _selectedSector == 'Villa Escuadrón Galilea'
                                    ? DropdownButtonFormField<String>(
                                        value: galileaNumbers.contains(_selectedHouseNumber)
                                            ? _selectedHouseNumber
                                            : galileaNumbers.first,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: '5. N° de Casa *',
                                          prefixIcon: Icon(Icons.home),
                                        ),
                                        items: galileaNumbers.map((n) {
                                          return DropdownMenuItem(
                                            value: n,
                                            child: Text(
                                              '#$n',
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          if (val != null) setState(() => _selectedHouseNumber = val);
                                        },
                                      )
                                    : TextFormField(
                                        controller: _customHouseCtrl,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: '5. N° de Casa *',
                                          hintText: 'Ej. 145',
                                          prefixIcon: Icon(Icons.home),
                                        ),
                                        validator: NeighborhoodLocations.validateHouseNumber,
                                      ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<String>(
                                  value: _selectedInterior,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Interior / Depto',
                                  ),
                                  items: NeighborhoodLocations.interiorOptions.map((opt) {
                                    return DropdownMenuItem(
                                      value: opt,
                                      child: Text(opt, style: const TextStyle(fontSize: 12)),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedInterior = val);
                                  },
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 12),

                          // DATOS PERSONALES
                          Row(
                            children: [
                              const Icon(Icons.person_pin_outlined, color: AppColors.steelBlue, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Datos del Residente Titular',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.brandNavyOf(context),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _firstNameCtrl,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Nombre(s) *',
                              hintText: 'Ej. Juan Carlos',
                              prefixIcon: Icon(Icons.person),
                            ),
                            validator: (v) => NeighborhoodLocations.validateHumanName(v, 'Nombre'),
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _lastName1Ctrl,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Primer Apellido (Paterno) *',
                              hintText: 'Ej. González',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            validator: (v) => NeighborhoodLocations.validateHumanName(v, 'Primer apellido'),
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _lastName2Ctrl,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Segundo Apellido (Materno) *',
                              hintText: 'Ej. Soto',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            validator: (v) => NeighborhoodLocations.validateHumanName(v, 'Segundo apellido'),
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Teléfono Móvil (Celular) (Opcional)',
                              hintText: 'Ej. 9 1234 5678',
                              prefixIcon: Icon(Icons.phone_android),
                              prefixText: '+56 ',
                              helperText: 'Opcional. Te permitirá restaurar tu cuenta si reinstalas la app',
                            ),
                            validator: (v) => NeighborhoodLocations.validateChileanPhone(v, isOptional: true),
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _pinCtrl,
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            maxLength: 4,
                            decoration: const InputDecoration(
                              labelText: 'Crea tu PIN de Seguridad (4 dígitos) *',
                              hintText: 'Ej. 1234',
                              prefixIcon: Icon(Icons.password),
                              helperText: 'Te servirá para restaurar tu cuenta si reinstalas la app',
                            ),
                            validator: NeighborhoodLocations.validatePin,
                          ),
                          const SizedBox(height: 20),

                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _submitNeighbor,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? const Color(0xFF2563EB) : AppColors.brandNavy,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                    )
                                  : const Text(
                                      'VINCULAR Y REGISTRAR VIVIENDA',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // TARJETA DE RECUPERACIÓN / RESTAURAR CUENTA TRAS REINSTALAR
                Card(
                  elevation: isDark ? 0 : 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: isDark ? const BorderSide(color: AppColors.darkBorder, width: 1) : BorderSide.none,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Form(
                      key: _restoreFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.restore_page_outlined, color: AppColors.steelBlue, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                'Restaurar Cuenta Existente',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.brandNavyOf(context),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '¿Desinstalaste la app o cambiaste de teléfono? No crees otro perfil; restaura tu vivienda registrada aquí mismo con tu PIN:',
                            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondaryOf(context)),
                          ),
                          const SizedBox(height: 16),

                          // Toggle de método de búsqueda
                          Row(
                            children: [
                              Expanded(
                                child: ChoiceChip(
                                  label: const Text('Por Teléfono Móvil', style: TextStyle(fontSize: 12)),
                                  selected: _restoreByPhone,
                                  onSelected: (val) => setState(() => _restoreByPhone = true),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ChoiceChip(
                                  label: const Text('Por Domicilio Villa', style: TextStyle(fontSize: 12)),
                                  selected: !_restoreByPhone,
                                  onSelected: (val) => setState(() => _restoreByPhone = false),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          if (_restoreByPhone) ...[
                            TextFormField(
                              controller: _restorePhoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Teléfono Móvil Registrado *',
                                hintText: 'Ej. 9 1234 5678',
                                prefixIcon: Icon(Icons.phone_android),
                                prefixText: '+56 ',
                              ),
                              validator: (v) {
                                if (!_restoreByPhone) return null;
                                return NeighborhoodLocations.validateChileanPhone(v);
                              },
                            ),
                          ] else ...[
                            DropdownButtonFormField<String>(
                              value: streets.contains(_restoreStreet) ? _restoreStreet : streets.first,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Pasaje / Calle en Villa Galilea *',
                                prefixIcon: Icon(Icons.add_road),
                              ),
                              items: streets.map((st) {
                                return DropdownMenuItem(value: st, child: Text(st, style: const TextStyle(fontSize: 13)));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _restoreStreet = val);
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _restoreHouseCtrl,
                              keyboardType: TextInputType.text,
                              decoration: const InputDecoration(
                                labelText: 'Número de Casa Registrado *',
                                hintText: 'Ej. 2430 o 2430 (Depto B)',
                                prefixIcon: Icon(Icons.home),
                              ),
                              validator: (v) {
                                if (_restoreByPhone) return null;
                                if (v == null || v.trim().isEmpty) return 'Ingresa el número de casa';
                                return null;
                              },
                            ),
                          ],

                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _restorePinCtrl,
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            maxLength: 4,
                            decoration: const InputDecoration(
                              labelText: 'Tu PIN de 4 dígitos *',
                              hintText: 'Ej. 1234',
                              prefixIcon: Icon(Icons.lock_outline),
                              helperText: 'Si te registraste en una versión anterior sin PIN, ingresa 1234',
                            ),
                            validator: NeighborhoodLocations.validatePin,
                          ),

                          const SizedBox(height: 20),

                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _submitRestoreAccount,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                    )
                                  : const Text(
                                      'INICIAR SESIÓN / RESTAURAR MI VIVIENDA',
                                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, letterSpacing: 0.6),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Botón Administrador
              Center(
                child: TextButton.icon(
                  onPressed: _isSaving ? null : _handleAdminAccess,
                  icon: Icon(
                    Icons.security,
                    size: 18,
                    color: AppColors.textSecondaryOf(context),
                  ),
                  label: Text(
                    '¿Eres el Administrador? Configurar o Acceder',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondaryOf(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
