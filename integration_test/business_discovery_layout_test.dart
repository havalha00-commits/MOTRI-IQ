import 'package:integration_test/integration_test.dart';
import '../test/business_discovery_polish_test.dart' as checks;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  checks.main();
}
