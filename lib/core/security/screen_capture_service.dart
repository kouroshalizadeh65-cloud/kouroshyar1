import 'package:flutter/services.dart';

/// Controls whether Android allows screenshots, screen recording and the
/// Recent Apps preview. Android starts in protected mode and this setting is
/// applied after the local security record has been loaded.
class ScreenCaptureService {
  static const MethodChannel _channel = MethodChannel('kouroshyar/privacy');

  static Future<void> setAllowed(bool allowed) async {
    try {
      await _channel.invokeMethod<void>('setScreenCaptureAllowed', <String, Object>{
        'allowed': allowed,
      });
    } on MissingPluginException {
      // Non-Android platforms do not expose this channel.
    } on PlatformException {
      // Keep the current secure window state if Android rejects the request.
    }
  }
}
