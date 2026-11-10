import 'package:integration_test/integration_test.dart';
import '../test/market_details_polish_test.dart' as checks;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  checks.main();
}
