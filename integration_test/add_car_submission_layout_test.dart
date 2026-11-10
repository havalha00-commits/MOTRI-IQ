import 'package:integration_test/integration_test.dart';
import '../test/add_car_submission_polish_test.dart' as scenarios;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  scenarios.main();
}
