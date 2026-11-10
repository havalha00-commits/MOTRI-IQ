import 'package:integration_test/integration_test.dart';
import '../test/account_feed_session_test.dart' as checks;
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  checks.main();
}
