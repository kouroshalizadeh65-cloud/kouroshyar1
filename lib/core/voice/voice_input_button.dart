import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({
    super.key,
    required this.onText,
    this.label = 'تایپ صوتی',
  });

  final ValueChanged<String> onText;
  final String label;

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  bool _initializing = false;
  String? _lastVoiceError;

  Future<void> _toggle() async {
    if (_initializing) return;

    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    setState(() {
      _initializing = true;
      _lastVoiceError = null;
    });

    bool ready = false;
    try {
      ready = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() => _listening = false);
          }
        },
        onError: (error) {
          if (!mounted) return;
          _lastVoiceError = error.errorMsg.toString();
          setState(() => _listening = false);
          _showVoiceHelp(_messageForVoiceError(_lastVoiceError));
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _initializing = false);
        _showVoiceHelp(_speechServiceMessage);
      }
      return;
    }

    if (!mounted) return;
    setState(() => _initializing = false);

    if (!ready) {
      final message = _isPermissionError(_lastVoiceError) ? _microphonePermissionMessage : _speechServiceMessage;
      _showVoiceHelp(message);
      return;
    }

    String? localeId;
    try {
      final locales = await _speech.locales();
      final faLocales = locales.where((l) => l.localeId.toLowerCase().startsWith('fa')).toList();
      if (faLocales.isEmpty) {
        _showVoiceHelp(_persianLocaleMessage);
        return;
      }
      localeId = faLocales.first.localeId;
    } catch (_) {
      _showVoiceHelp(_speechServiceMessage);
      return;
    }

    setState(() => _listening = true);
    try {
      await _speech.listen(
        localeId: localeId,
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) widget.onText(words);
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _listening = false);
      _showVoiceHelp(_speechServiceMessage);
    }
  }

  static const String _microphonePermissionMessage =
      'مجوز میکروفون داده نشده است. از تنظیمات گوشی، مجوز میکروفون کوروش‌یار را فعال کن یا فعلاً از میکروفون صفحه‌کلید استفاده کن.';

  static const String _speechServiceMessage =
      'سرویس گفتار گوشی آماده نیست. سرویس گفتار/Google Speech را بررسی کن یا فعلاً از میکروفون صفحه‌کلید استفاده کن.';

  static const String _persianLocaleMessage =
      'زبان فارسی برای تایپ صوتی در این گوشی فعال نیست. زبان فارسی را در سرویس گفتار گوشی فعال کن یا فعلاً از میکروفون صفحه‌کلید استفاده کن.';

  String _messageForVoiceError(String? error) {
    if (_isPermissionError(error)) return _microphonePermissionMessage;
    return _speechServiceMessage;
  }

  bool _isPermissionError(String? error) {
    final value = (error ?? '').toLowerCase();
    return value.contains('permission') || value.contains('not_allowed') || value.contains('notallowed') || value.contains('denied');
  }

  void _showVoiceHelp(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _toggle,
      icon: Icon(_listening ? Icons.stop_circle : Icons.mic),
      label: Text(_initializing ? 'بررسی میکروفون...' : (_listening ? 'توقف ضبط' : widget.label)),
    );
  }
}
