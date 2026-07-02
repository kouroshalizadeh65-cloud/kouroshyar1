import 'dart:io';

class DocumentTextTools {
  static Future<String> readPlainTextIfPossible(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return '';
    }

    final lower = path.toLowerCase();
    if (lower.endsWith('.txt')) {
      return file.readAsString();
    }

    // PDF/OCR کامل در نسخه بعدی توسعه داده می‌شود.
    // این نسخه مسیر فایل را نگه می‌دارد و برای فایل txt متن را می‌خواند.
    return '';
  }
}
