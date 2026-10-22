// یک بلوکِ متنِ تشخیص‌داده‌شده روی عکس (برای ترجمه‌ی عکسیِ صفحه‌ی PDF).
// مختصات نسبی‌اند (۰ تا ۱ نسبت به عرض/ارتفاعِ عکس) تا به اندازه‌ی عکس وابسته نباشند.
class OcrBlock {
  final String text;
  final double left;
  final double top;
  final double width;
  final double height;
  const OcrBlock(this.text, this.left, this.top, this.width, this.height);
}
