import 'package:flutter/material.dart';
import '../ai/ai_settings_screen.dart';
import '../backup/backup_screen.dart';
import '../privacy/privacy_center_screen.dart';
import '../profile/profile_screen.dart';
import '../security/security_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('پروفایل و اطلاعات وکالتی'),
            subtitle: const Text('نام کاربری و اجازه استفاده از مشخصات در متون حقوقی'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text('امنیت برنامه'),
            subtitle: const Text('رمز، قفل برنامه و اثر انگشت'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SecurityScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip),
            title: const Text('حریم خصوصی'),
            subtitle: const Text('ذخیره‌سازی محلی و منع ارسال اطلاعات بدون اجازه کاربر'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyCenterScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('پشتیبان‌گیری'),
            subtitle: const Text('پشتیبان خودکار، چرخشی و بازیابی امن'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.smart_toy),
            title: const Text('هوش مصنوعی'),
            subtitle: const Text('فعال‌سازی اختیاری با کلید API شخصی و تأیید قبل از ارسال متن'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiSettingsScreen())),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info),
            title: Text('نسخه برنامه'),
            subtitle: Text('کوروش‌یار v3.5.0'),
          ),
          const ListTile(
            leading: Icon(Icons.phone_android),
            title: Text('وضعیت نسخه فعلی'),
            subtitle: Text('نسخه بازطراحی هسته با خانه جدید، ثبت سریع شناور و مسیرهای ساده‌تر'),
          ),
        ],
      ),
    );
  }
}
