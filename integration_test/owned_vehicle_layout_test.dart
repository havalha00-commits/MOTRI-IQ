import 'package:integration_test/integration_test.dart';
import '../test/owned_vehicle_polish_test.dart' as scenarios;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  scenarios.main();
}
