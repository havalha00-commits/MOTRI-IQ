import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/material.dart' show Icons;

/// One rounded symbol family for navigation and common app actions.
/// Keep directional back/disclosure icons supplied by Flutter so they mirror
/// automatically with the app's text direction.
abstract final class AppIcons {
  // Flutter mirrors this forward disclosure in RTL. Do not choose a left
  // glyph manually: both Material chevrons already match text direction.
  static const disclosure = Icons.chevron_right_rounded;
  static const schedule = Symbols.schedule_rounded;
  static const camera = Symbols.photo_camera_rounded;
  static const imageUnavailable = Symbols.broken_image_rounded;
  static const addPhoto = Symbols.add_photo_alternate_rounded;
  static const close = Symbols.close_rounded;
  static const edit = Symbols.edit_rounded;
  static const delete = Symbols.delete_rounded;
  static const category = Symbols.category_rounded;
  static const work = Symbols.work_rounded;
  static const inbox = Symbols.inbox_rounded;
  static const retry = Symbols.refresh_rounded;
  static const cloudOff = Symbols.cloud_off_rounded;
  static const locked = Symbols.lock_rounded;
  static const chat = Symbols.chat_bubble_rounded;
  static const reviews = Symbols.reviews_rounded;
  static const following = Symbols.group_rounded;
  static const home = Symbols.home_rounded;
  static const cars = Symbols.directions_car_rounded;
  static const market = Symbols.storefront_rounded;
  static const search = Symbols.search_rounded;
  static const account = Symbols.person_rounded;
  static const add = Symbols.add_rounded;
  static const filters = Symbols.tune_rounded;
  static const settings = Symbols.settings_rounded;
  static const support = Symbols.support_agent_rounded;
  static const language = Symbols.language_rounded;
  static const favorite = Symbols.favorite_rounded;
  static const share = Symbols.share_rounded;
  static const location = Symbols.location_on_rounded;
  static const notifications = Symbols.notifications_rounded;
  static const receipt = Symbols.receipt_long_rounded;
  static const history = Symbols.history_rounded;
  static const campaign = Symbols.campaign_rounded;
  static const offer = Symbols.local_offer_rounded;
  static const logout = Symbols.logout_rounded;
  static const call = Symbols.call_rounded;
  static const compare = Symbols.compare_arrows_rounded;
}
