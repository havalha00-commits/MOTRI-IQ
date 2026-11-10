import 'package:flutter/widgets.dart';

/// Advertising is disabled for the first release. The ad SDK is not packaged.
class HomeBannerAd extends StatelessWidget {
  const HomeBannerAd({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// No consent form is needed while the advertising SDK is absent.
class AdPrivacyOptionsButton extends StatelessWidget {
  const AdPrivacyOptionsButton({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
