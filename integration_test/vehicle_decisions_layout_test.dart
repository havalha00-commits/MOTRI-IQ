import 'package:integration_test/integration_test.dart';
import '../test/vehicle_decisions_polish_test.dart' as scenarios;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  scenarios.main();
}
