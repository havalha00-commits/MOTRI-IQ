import 'package:integration_test/integration_test.dart';
import '../test/startup_handoff_test.dart' as scenarios;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  scenarios.main();
}
