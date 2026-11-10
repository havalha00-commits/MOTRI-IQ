import 'package:integration_test/integration_test.dart';
import '../test/seller_profile_polish_test.dart' as profiles;
import '../test/photo_gallery_test.dart' as galleries;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  profiles.main();
  galleries.main();
}
