import 'dart:convert';
import 'package:http/http.dart' as http;

class OpenAiService {
  final String apiKey;
  final String model;

  OpenAiService({
    required this.apiKey,
    required this.model,
  });

  Future<String> sendPrompt(String prompt) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('کلید API ثبت نشده است.');
    }

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/responses'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model.trim().isEmpty ? 'gpt-4.1-mini' : model.trim(),
        'input': prompt,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('خطا در اتصال به هوش مصنوعی: ${response.statusCode}\n${response.body}');
    }

    final data = jsonDecode(response.body);

    if (data is Map && data['output_text'] is String) {
      return data['output_text'] as String;
    }

    final buffer = StringBuffer();
    final output = data['output'];
    if (output is List) {
      for (final item in output) {
        if (item is Map && item['content'] is List) {
          for (final c in item['content']) {
            if (c is Map && c['text'] is String) {
              buffer.writeln(c['text']);
            }
          }
        }
      }
    }

    final result = buffer.toString().trim();
    if (result.isEmpty) {
      return 'پاسخی دریافت شد، اما متن قابل نمایش استخراج نشد.';
    }
    return result;
  }
}
