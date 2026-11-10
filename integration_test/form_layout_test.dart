import 'package:integration_test/integration_test.dart';
import '../test/form_polish_test.dart' as scenarios;

/// Native layout/validation checks use a local HTTP/auth fixture client. The
/// suite rejects listing uploads, purchases and form submissions.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  scenarios.main();
}
