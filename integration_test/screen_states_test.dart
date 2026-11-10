import 'package:integration_test/integration_test.dart';
import '../test/state_polish_test.dart' as scenarios;

/// Run the same page-level recovery and large-text scenarios on native Flutter
/// rendering. The scenario suite supplies an isolated HTTP/auth fixture backend;
/// no production account, wallet or moderation operation is sent.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  scenarios.main();
}
