پچ Primary School ▸ A2 (لغات + مکالمه‌ها) — جایگزین زیپ قبلی primary-school-a2-vocab-patch
فایل‌های داده:
- assets/data/primary_a2.json (لغات: ۲۱ موضوع، (لغات) لغت/عبارت)
- assets/data/primary_a2_conversations_index.json
- assets/data/conversations/p-a2-*.json (۲۴ موضوع، ۱۲۰ سناریو، ۷۲۱ جمله)
فایل‌های Dart (جایگزین کامل؛ اگر بعد از آپلود قبلی تغییر کرده‌اند اول مقایسه کن):
- lib/core/providers/primary_school_provider.dart
- lib/core/data/conversation_repository.dart
- lib/core/usage/conversations_index.dart
- lib/features/tabs/primary_school_view.dart
- lib/features/tabs/conversations_tab.dart
- lib/features/words/widgets/stage_chips_bar.dart
- lib/core/constants/topic_titles.dart
- lib/core/constants/topic_icons.dart
هنوز کامپایل و اجرا نشده.

افزوده‌ی جدید — تمرین ساخت سؤال (A2):
- assets/data/primary_a2_questions.json (۱۰ مجموعه، ۸۰ سؤال با معنی فارسی)
- lib/features/tabs/question_practice_page.dart (فایل جدید)
- primary_school_view.dart: کارت «تمرین ساخت سؤال» بالای شبکه‌ی موضوع‌های A2 (فقط در تب لغات)

افزوده‌ی جدید — تمرین درک شنیداری (A2):
- assets/data/primary_a2_listening.json (۱۰ مجموعه، ۴۰ متن کوتاه، ۸۰ سؤال چهارگزینه‌ای)
- lib/features/tabs/listening_practice_page.dart (فایل جدید)
- primary_school_view.dart: کارت «تمرین درک شنیداری» بالای کارت «ساخت سؤال» (فقط A2، فقط تب لغات)

افزوده‌ی جدید — تمرین نوشتن پیام و ایمیل (A2):
- assets/data/primary_a2_writing.json (۱۰ مجموعه، ۳۰ تمرین؛ هر کدام چک‌لیست، عبارت‌های کمکی و جواب نمونه)
- lib/features/tabs/writing_practice_page.dart (فایل جدید)
- primary_school_view.dart: کارت سوم «تمرین نوشتن پیام و ایمیل» (فقط A2، فقط تب لغات)
