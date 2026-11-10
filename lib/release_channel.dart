import 'package:flutter/foundation.dart';

const bool playStoreBuild = bool.fromEnvironment('PLAY_STORE_BUILD');

/// Digital placements need Play Billing before being sold in the Play app.
bool get restrictPaidFeatures =>
    playStoreBuild && !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

const accountDeletionUrl =
    'https://motri-iq-account-deletion.me-0eca.chatgpt.site/';
