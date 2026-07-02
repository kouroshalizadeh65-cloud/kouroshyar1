import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/app_database.dart';
import '../../database/database_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final nameController = TextEditingController();
  final titleController = TextEditingController();
  final licenseController = TextEditingController();
  final barController = TextEditingController();

  bool loaded = false;
  bool useNameInLegalTexts = false;
  bool useLicenseInLegalTexts = false;
  bool useBarInLegalTexts = false;

  @override
  void dispose() {
    nameController.dispose();
    titleController.dispose();
    licenseController.dispose();
    barController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('ثبت‌نام / پروفایل کاربر')),
      body: FutureBuilder<List<UserProfile>>(
        future: db.select(db.userProfiles).get(),
        builder: (context, snapshot) {
          final current = (snapshot.data ?? const <UserProfile>[]).isNotEmpty ? (snapshot.data ?? const <UserProfile>[]).first : null;

          if (!loaded && current != null) {
            loaded = true;
            nameController.text = current.displayName ?? '';
            titleController.text = current.legalTitle ?? '';
            licenseController.text = current.licenseNumber ?? '';
            barController.text = current.barAssociation ?? '';
            useNameInLegalTexts = current.useNameInLegalTexts;
            useLicenseInLegalTexts = current.useLicenseInLegalTexts;
            useBarInLegalTexts = current.useBarInLegalTexts;
          }

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
              const Card(
                child: ListTile(
                  leading: Icon(Icons.person),
                  title: Text('اطلاعات پروفایل'),
                  subtitle: Text('نام و مشخصات فقط با اجازه خودت در پیام ورود یا متون حقوقی استفاده می‌شود.'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'نام کاربری', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'عنوان اختیاری، مثل وکیل پایه یک', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: licenseController,
                decoration: const InputDecoration(labelText: 'شماره پروانه، اختیاری', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: barController,
                decoration: const InputDecoration(labelText: 'کانون / مرکز، اختیاری', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: useNameInLegalTexts,
                title: const Text('استفاده از نام کاربری در متون حقوقی'),
                subtitle: const Text('مثل: اینجانب [نام کاربری] به وکالت از...'),
                onChanged: (v) => setState(() => useNameInLegalTexts = v),
              ),
              SwitchListTile(
                value: useLicenseInLegalTexts,
                title: const Text('استفاده از شماره پروانه در متون حقوقی'),
                onChanged: (v) => setState(() => useLicenseInLegalTexts = v),
              ),
              SwitchListTile(
                value: useBarInLegalTexts,
                title: const Text('استفاده از کانون / مرکز در متون حقوقی'),
                onChanged: (v) => setState(() => useBarInLegalTexts = v),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  final displayName = nameController.text.trim();
                  final legalTitle = titleController.text.trim();
                  final licenseNumber = licenseController.text.trim();
                  final barAssociation = barController.text.trim();

                  if (displayName.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('حداقل نام کاربری را وارد کنید.')),
                    );
                    return;
                  }

                  final existing = await db.select(db.userProfiles).get();
                  final companion = UserProfilesCompanion.insert(
                    displayName: Value(displayName),
                    legalTitle: Value(legalTitle),
                    licenseNumber: Value(licenseNumber),
                    barAssociation: Value(barAssociation),
                    useNameInLegalTexts: Value(useNameInLegalTexts),
                    useLicenseInLegalTexts: Value(useLicenseInLegalTexts),
                    useBarInLegalTexts: Value(useBarInLegalTexts),
                  );

                  if (existing.isEmpty) {
                    await db.into(db.userProfiles).insert(companion);
                  } else {
                    await db.update(db.userProfiles).replace(
                          existing.first.copyWith(
                            displayName: Value(displayName),
                            legalTitle: Value(legalTitle),
                            licenseNumber: Value(licenseNumber),
                            barAssociation: Value(barAssociation),
                            useNameInLegalTexts: useNameInLegalTexts,
                            useLicenseInLegalTexts: useLicenseInLegalTexts,
                            useBarInLegalTexts: useBarInLegalTexts,
                            updatedAt: DateTime.now(),
                          ),
                        );
                  }

                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پروفایل ذخیره شد')));
                },
                icon: const Icon(Icons.save),
                label: const Text('ذخیره پروفایل'),
              ),
              ],
            ),
          );
        },
      ),
    );
  }
}
