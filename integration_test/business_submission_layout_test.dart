import 'package:integration_test/integration_test.dart';
import '../test/business_submission_polish_test.dart' as scenarios;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  scenarios.main();
}
