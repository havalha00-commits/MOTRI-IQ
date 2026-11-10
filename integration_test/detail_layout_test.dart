import 'package:integration_test/integration_test.dart';
import '../test/detail_polish_test.dart' as details;
import '../test/photo_gallery_test.dart' as galleries;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  details.main();
  galleries.main();
}
