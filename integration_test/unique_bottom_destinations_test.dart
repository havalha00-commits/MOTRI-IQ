import 'package:integration_test/integration_test.dart';
import '../test/home_empty_sections_test.dart' as scenarios;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  scenarios.main();
}
