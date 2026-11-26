import 'package:flutter/material.dart';

import 'topic_icons.dart' show TopicVisual;

// 🎨 آیکون + رنگِ دسته‌های تب‌های لغات (دیکشنری من / Vocab in use / Slang)
// همان پالت و همان استایلِ topic_icons.dart (کارت‌های تب مکالمه).

const _teal = Color(0xFF1B8578);
const _gold = Color(0xFFC99A2E);
const _purple = Color(0xFF7A5FA8);
const _rose = Color(0xFFB85A72);
const _blue = Color(0xFF3A7CA5);
const _green = Color(0xFF2E9E7B);
const _orange = Color(0xFFD9752E);
const _brown = Color(0xFF8B5E3C);

const TopicVisual kAllCategoriesVisual =
    TopicVisual(Icons.apps_rounded, _teal);

const Map<String, TopicVisual> _dict = {
  'food': TopicVisual(Icons.restaurant_rounded, _orange),
  'home': TopicVisual(Icons.cottage_rounded, _brown),
  'family': TopicVisual(Icons.family_restroom_rounded, _purple),
  'feelings': TopicVisual(Icons.mood_rounded, _rose),
  'people': TopicVisual(Icons.fingerprint_rounded, _rose),
  'health': TopicVisual(Icons.medical_services_rounded, _rose),
  'work': TopicVisual(Icons.work_rounded, _blue),
  'shopping': TopicVisual(Icons.shopping_cart_rounded, _orange),
  'school': TopicVisual(Icons.school_rounded, _purple),
  'travel': TopicVisual(Icons.flight_takeoff_rounded, _blue),
  'nature': TopicVisual(Icons.park_rounded, _green),
  'tech': TopicVisual(Icons.devices_other_rounded, _blue),
  'leisure': TopicVisual(Icons.sports_soccer_rounded, _orange),
  'time': TopicVisual(Icons.schedule_rounded, _gold),
  'talk': TopicVisual(Icons.forum_rounded, _teal),
  'actions': TopicVisual(Icons.directions_run_rounded, _green),
  'situations': TopicVisual(Icons.alt_route_rounded, _purple),
  'society': TopicVisual(Icons.gavel_rounded, _brown),
  'other': TopicVisual(Icons.category_rounded, _teal),
  // 🎒 موضوع‌های Primary School
  'alphabet': TopicVisual(Icons.abc_rounded, _purple),
  'numbers': TopicVisual(Icons.pin_rounded, _gold),
  'colors': TopicVisual(Icons.palette_rounded, _rose),
  'shapes': TopicVisual(Icons.interests_rounded, _blue),
  'animals': TopicVisual(Icons.pets_rounded, _brown),
  'body': TopicVisual(Icons.accessibility_new_rounded, _teal),
  'objects': TopicVisual(Icons.backpack_rounded, _orange),
  'greetings': TopicVisual(Icons.waving_hand_rounded, _teal),
  'sentences': TopicVisual(Icons.chat_bubble_rounded, _green),
  // 🎒 موضوع‌های Primary A2 (موضوع‌های قدیمی)
  'clothes': TopicVisual(Icons.checkroom_rounded, _rose),
  'restaurant': TopicVisual(Icons.restaurant_menu_rounded, _orange),
  'places': TopicVisual(Icons.location_city_rounded, _blue),
  'directions': TopicVisual(Icons.directions_rounded, _green),
  'hotel': TopicVisual(Icons.hotel_rounded, _blue),
  'routine': TopicVisual(Icons.alarm_rounded, _gold),
  'weather': TopicVisual(Icons.wb_sunny_rounded, _gold),
  'hobbies': TopicVisual(Icons.sports_esports_rounded, _orange),
  'pharmacy': TopicVisual(Icons.local_pharmacy_rounded, _rose),
  'phrases': TopicVisual(Icons.chat_bubble_rounded, _teal),
  'past_future': TopicVisual(Icons.history_rounded, _purple),
  'messages': TopicVisual(Icons.mail_rounded, _blue),
  'jobs': TopicVisual(Icons.work_rounded, _blue),
  'transport': TopicVisual(Icons.directions_bus_rounded, _orange),
  'celebrations': TopicVisual(Icons.cake_rounded, _rose),
  'comparison': TopicVisual(Icons.compare_arrows_rounded, _teal),
  // 🏫 موضوع‌های مدرسه‌ایِ Primary A2
  'instructions': TopicVisual(Icons.record_voice_over_rounded, _purple),
  'science': TopicVisual(Icons.science_rounded, _teal),
  'math': TopicVisual(Icons.calculate_rounded, _gold),
  'geography': TopicVisual(Icons.public_rounded, _blue),
  'countries': TopicVisual(Icons.flag_rounded, _rose),
  'plants': TopicVisual(Icons.local_florist_rounded, _green),
  'habitats': TopicVisual(Icons.forest_rounded, _brown),
  'art': TopicVisual(Icons.brush_rounded, _rose),
  'music': TopicVisual(Icons.music_note_rounded, _purple),
  'pe': TopicVisual(Icons.sports_soccer_rounded, _orange),
  'computers': TopicVisual(Icons.computer_rounded, _blue),
  'community': TopicVisual(Icons.groups_rounded, _teal),
  'safety': TopicVisual(Icons.warning_amber_rounded, _gold),
  'environment': TopicVisual(Icons.eco_rounded, _green),
  'space': TopicVisual(Icons.star_rounded, _purple),
  'habits': TopicVisual(Icons.spa_rounded, _teal),
  'stories': TopicVisual(Icons.auto_stories_rounded, _brown),
  'cooking': TopicVisual(Icons.kitchen_rounded, _orange),
  'vehicles': TopicVisual(Icons.local_shipping_rounded, _blue),
  'friends': TopicVisual(Icons.people_alt_rounded, _rose),
  'history': TopicVisual(Icons.account_balance_rounded, _brown),
  // 🧸 موضوع‌های تازه‌ی Preschool
  'toys': TopicVisual(Icons.toys_rounded, _rose),
  'opposites': TopicVisual(Icons.swap_vert_rounded, _teal),
  'position': TopicVisual(Icons.pin_drop_rounded, _blue),
  'pronouns': TopicVisual(Icons.text_fields_rounded, _purple),
  // 📚 موضوع‌های گرامریِ Lower Secondary (B1)
  'prep_place': TopicVisual(Icons.explore_rounded, _blue),
  'prep_time': TopicVisual(Icons.schedule_rounded, _blue),
  'articles': TopicVisual(Icons.text_fields_rounded, _purple),
  'quantifiers': TopicVisual(Icons.straighten_rounded, _gold),
  'adv_freq': TopicVisual(Icons.swap_horiz_rounded, _green),
  'adv_manner': TopicVisual(Icons.speed_rounded, _orange),
  'adv_place': TopicVisual(Icons.pin_drop_rounded, _teal),
  'helpers': TopicVisual(Icons.engineering_rounded, _orange),
  'hygiene': TopicVisual(Icons.clean_hands_rounded, _teal),
  'senses': TopicVisual(Icons.visibility_rounded, _purple),
  'movement': TopicVisual(Icons.directions_walk_rounded, _green),
  'size': TopicVisual(Icons.straighten_rounded, _blue),
};

const Map<String, TopicVisual> _slang = {
  'people': TopicVisual(Icons.fingerprint_rounded, _rose),
  'emotions': TopicVisual(Icons.mood_rounded, _rose),
  'love': TopicVisual(Icons.favorite_rounded, _rose),
  'fun': TopicVisual(Icons.celebration_rounded, _gold),
  'food': TopicVisual(Icons.restaurant_rounded, _orange),
  'money': TopicVisual(Icons.payments_rounded, _green),
  'work': TopicVisual(Icons.work_rounded, _blue),
  'school': TopicVisual(Icons.school_rounded, _purple),
  'crime': TopicVisual(Icons.local_police_rounded, _brown),
  'health': TopicVisual(Icons.medical_services_rounded, _rose),
  'travel': TopicVisual(Icons.directions_bus_rounded, _orange),
  'home': TopicVisual(Icons.cottage_rounded, _brown),
  'tech': TopicVisual(Icons.smartphone_rounded, _blue),
  'exclaim': TopicVisual(Icons.bolt_rounded, _gold),
  'idioms': TopicVisual(Icons.format_quote_rounded, _purple),
  'phrases': TopicVisual(Icons.chat_bubble_rounded, _teal),
  'modern': TopicVisual(Icons.trending_up_rounded, _purple),
  'abbrev': TopicVisual(Icons.short_text_rounded, _blue),
  'proverbs': TopicVisual(Icons.auto_stories_rounded, _brown),
  'other': TopicVisual(Icons.category_rounded, _teal),
};

const Map<String, TopicVisual> _vocab = {
  'health': TopicVisual(Icons.medical_services_rounded, _rose),
  'learning': TopicVisual(Icons.translate_rounded, _teal),
  'people': TopicVisual(Icons.fingerprint_rounded, _rose),
  'feelings': TopicVisual(Icons.mood_rounded, _rose),
  'home': TopicVisual(Icons.cottage_rounded, _brown),
  'money': TopicVisual(Icons.account_balance_wallet_rounded, _green),
  'food': TopicVisual(Icons.restaurant_rounded, _orange),
  'city': TopicVisual(Icons.location_city_rounded, _blue),
  'nature': TopicVisual(Icons.park_rounded, _green),
  'education': TopicVisual(Icons.school_rounded, _purple),
  'work': TopicVisual(Icons.business_center_rounded, _blue),
  'leisure': TopicVisual(Icons.fitness_center_rounded, _orange),
  'travel': TopicVisual(Icons.travel_explore_rounded, _blue),
  'tech': TopicVisual(Icons.devices_other_rounded, _blue),
  'society': TopicVisual(Icons.public_rounded, _teal),
  'numbers': TopicVisual(Icons.pin_rounded, _gold),
  'talk': TopicVisual(Icons.forum_rounded, _teal),
  'verbs': TopicVisual(Icons.directions_run_rounded, _green),
  'words': TopicVisual(Icons.spellcheck_rounded, _purple),
  'style': TopicVisual(Icons.style_rounded, _rose),
};

/// [list] یکی از 'daily' (دیکشنری من) / 'slang' / 'vocab'
TopicVisual categoryVisual(String list, String key) {
  final m = list == 'slang' ? _slang : (list == 'vocab' ? _vocab : _dict);
  return m[key] ?? const TopicVisual(Icons.category_rounded, _teal);
}
