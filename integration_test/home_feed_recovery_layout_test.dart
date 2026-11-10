import 'package:integration_test/integration_test.dart';
import '../test/home_feed_recovery_test.dart' as checks;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  checks.main();
}
