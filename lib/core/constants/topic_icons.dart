import 'package:flutter/material.dart';

/// آیکون اختصاصی هر موضوع — هم در لیست، هم در صفحه‌ی سناریو
IconData iconForTopic(String topic) {
  final t = topic.toLowerCase();

  // ═══ روزمره (انگلیسی) ═══
  if (t.contains('greetings')) return Icons.waving_hand_outlined;
  if (t.contains('introducing people')) return Icons.person_add_alt_1_outlined;
  if (t.contains('visiting an old friend')) return Icons.house_outlined;
  if (t.contains('getting acquainted')) return Icons.person_search_outlined;
  if (t.contains('accepting or refusing')) return Icons.mark_email_read_outlined;
  if (t.contains('invitations')) return Icons.mail_outline;
  if (t.contains('saying goodbye')) return Icons.door_front_door_outlined;
  if (t.contains('telephone')) return Icons.call_outlined;
  if (t.contains('transportation')) return Icons.directions_bus_outlined;
  if (t.contains('gas station')) return Icons.local_gas_station_outlined;
  if (t.contains('weather')) return Icons.wb_sunny_outlined;
  if (t.contains('restaurant') || t.contains('café') || t.contains('cafe')) return Icons.restaurant_outlined;
  if (t.contains('shopping (clothes')) return Icons.checkroom_outlined;
  if (t.contains('at a hotel')) return Icons.hotel_outlined;
  if (t.contains('health and doctor')) return Icons.medical_services_outlined;
  if (t.contains('directions') || t.contains('landmarks')) return Icons.explore_outlined;
  if (t.contains('plans and free time') || t.contains('hobbies')) return Icons.event_available_outlined;
  if (t.contains('work and workplace')) return Icons.work_outline;
  if (t.contains('time and appointments')) return Icons.schedule_outlined;
  if (t.contains('expressing opinions')) return Icons.emoji_emotions_outlined;
  if (t.contains('asking for help')) return Icons.help_outline;
  if (t.contains('politeness and compliments')) return Icons.volunteer_activism_outlined;
  if (t.contains('travel and experiences')) return Icons.travel_explore_outlined;
  if (t.contains('apologies and forgiveness')) return Icons.handshake_outlined;
  if (t.contains('family and cultural')) return Icons.family_restroom_outlined;
  if (t.contains('sports and fitness')) return Icons.fitness_center_outlined;
  if (t.contains('technology and communication')) return Icons.devices_other_outlined;
  if (t.contains('holidays and celebrations')) return Icons.celebration_outlined;
  if (t.contains('pets and animals')) return Icons.pets_outlined;
  if (t.contains('learning a language')) return Icons.translate_outlined;
  if (t.contains('emergency')) return Icons.emergency_outlined;
  if (t.contains('city attractions')) return Icons.location_city_outlined;
  if (t.contains('schools and education')) return Icons.school_outlined;
  if (t.contains('money and expenses')) return Icons.account_balance_wallet_outlined;
  if (t.contains('books and reading')) return Icons.menu_book_outlined;
  if (t.contains('environment and nature')) return Icons.eco_outlined;
  if (t.contains('cooking and recipes')) return Icons.restaurant_menu_outlined;
  if (t.contains('movies and tv')) return Icons.movie_outlined;
  if (t == 'music' || t.contains('|music|')) return Icons.music_note_outlined;
  if (t.contains('banking and financial')) return Icons.account_balance_outlined;
  if (t.contains('post office')) return Icons.local_post_office_outlined;
  if (t.contains('neighbors and community')) return Icons.diversity_3_outlined;
  if (t.contains('future plans and dreams')) return Icons.rocket_launch_outlined;
  if (t.contains('memories and past')) return Icons.history_outlined;

  // ═══ موضوعی (فارسی) ═══
  if (topic.contains('طبیعت')) return Icons.park_outlined;
  if (topic.contains('احساسات')) return Icons.mood_outlined;
  if (topic.contains('مذهب و سیاست')) return Icons.how_to_vote_outlined;
  if (topic.contains('خرید')) return Icons.shopping_cart_outlined;
  if (topic.contains('علوم')) return Icons.science_outlined;
  if (topic.contains('مسائل اجتماعی')) return Icons.public_outlined;
  if (topic.contains('فناوری')) return Icons.memory_outlined;
  if (topic.contains('سفر و گردشگری')) return Icons.flight_takeoff_outlined;
  if (topic.contains('غذا و آشپزی')) return Icons.soup_kitchen_outlined;
  if (topic.contains('جنگ')) return Icons.shield_outlined;
  if (topic.contains('شغل')) return Icons.badge_outlined;
  if (topic.contains('شخصیت')) return Icons.fingerprint_outlined;
  if (topic.contains('بدن انسان')) return Icons.accessibility_new_outlined;
  if (topic.contains('کسب و کار')) return Icons.business_center_outlined;
  if (topic.contains('لباس و مد')) return Icons.dry_cleaning_outlined;
  if (topic.contains('جرم و قانون')) return Icons.gavel_outlined;
  if (topic.contains('فرهنگ')) return Icons.theater_comedy_outlined;
  if (topic.contains('آموزش و تحصیل')) return Icons.school_outlined;
  if (topic.contains('رسانه')) return Icons.newspaper_outlined;
  if (topic.contains('حیوانات')) return Icons.pets_outlined;
  if (topic.contains('خانه')) return Icons.cottage_outlined;

  return Icons.chat_bubble_outline;
}

/// ۴ رنگ ملایم که بین کارت‌ها می‌چرخه
const List<Color> kTopicBadgeColors = [
  Color(0xFFEAF4F1), // سبز آبی
  Color(0xFFFBF0DA), // کرم
  Color(0xFFF3ECFB), // بنفش ملایم
  Color(0xFFFBE9E4), // صورتی-نارنجی
];
