import 'package:integration_test/integration_test.dart';
import '../test/car_requests_polish_test.dart' as suite;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suite.main();
}
