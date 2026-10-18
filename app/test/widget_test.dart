import 'package:flutter_test/flutter_test.dart';
import 'package:alerta_vecinal_app/models/alert_model.dart';

void main() {
  test('AlertModel serialization test', () {
    final alert = AlertModel(
      id: 'test_1',
      sender: 'Casa 10',
      notes: 'Prueba de alerta',
      timestamp: DateTime.now(),
      active: true,
    );

    final json = alert.toJson();
    expect(json['sender'], 'Casa 10');
    expect(json['active'], true);

    final restored = AlertModel.fromJson(json);
    expect(restored.sender, 'Casa 10');
  });

  test('AlertModel copyWith and extractCoordinates test', () {
    final alert = AlertModel(
      id: 'alert_101',
      sender: 'Juan Perez',
      notes: 'Humo detectado',
      timestamp: DateTime.now(),
      active: true,
      reportCode: '#REP-2026-001',
    );

    final modified = alert.copyWith(notes: 'Incendio controlado');
    expect(modified.notes, 'Incendio controlado');
    expect(modified.id, 'alert_101');
    expect(modified.reportCode, '#REP-2026-001');

    final (lat, lng) = AlertModel.extractCoordinates('-37.01234, -73.12345');
    expect(lat, -37.01234);
    expect(lng, -73.12345);
  });
}
