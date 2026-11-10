import 'package:integration_test/integration_test.dart';
import '../test/language_picker_polish_test.dart' as checks;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  checks.main();
}
