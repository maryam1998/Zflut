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
