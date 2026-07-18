# راهنمای ساده تنظیم امضای دائمی APK کوروش‌یار

از نسخه v3.6.40، APK release باید با کلید دائمی شما امضا شود. اگر Secrets را تنظیم نکنید، GitHub Actions عمداً متوقف می‌شود تا اشتباهاً APK با امضای موقت ساخته نشود.

## کاری که شما باید انجام دهید

### ۱) ساخت کلید امضا روی کامپیوتر

PowerShell یا CMD را باز کنید و این دستور را اجرا کنید:

```powershell
keytool -genkeypair -v -keystore kouroshyar-release-key.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias kouroshyar
```

از شما رمز می‌خواهد. یک رمز قوی انتخاب کنید و آن را در جای امن نگه دارید.

پیشنهاد:

```text
Alias: kouroshyar
فایل: kouroshyar-release-key.jks
رمز keystore: همان رمزی که انتخاب می‌کنید
رمز key: اگر رمز جدا نخواست، همان رمز keystore است
```

### ۲) تبدیل فایل امضا به Base64

در همان پوشه‌ای که فایل `kouroshyar-release-key.jks` ساخته شده، این دستور را بزنید:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("kouroshyar-release-key.jks")) | Set-Content "kouroshyar_keystore_base64.txt"
```

فایل `kouroshyar_keystore_base64.txt` ساخته می‌شود. متن داخل آن را باید در GitHub Secrets بگذارید.

### ۳) ثبت Secrets در GitHub

در مخزن GitHub بروید به:

```text
Settings → Secrets and variables → Actions → New repository secret
```

این ۴ Secret را بسازید:

```text
KOUROSHYAR_KEYSTORE_BASE64
```
مقدار: متن داخل فایل `kouroshyar_keystore_base64.txt`

```text
KOUROSHYAR_KEYSTORE_PASSWORD
```
مقدار: رمز keystore که انتخاب کردید

```text
KOUROSHYAR_KEY_PASSWORD
```
مقدار: رمز key؛ اگر رمز جدا ندادید، همان رمز keystore را بگذارید

```text
KOUROSHYAR_KEY_ALIAS
```
مقدار:

```text
kouroshyar
```

## نکته مهم

اگر با این کلید جدید APK بسازید، ممکن است اولین نسخه روی نسخه قبلی نصب نشود. در این حالت باید نسخه قبلی را از گوشی حذف کنید و بعد نسخه جدید را نصب کنید. از آن به بعد، اگر همیشه همین Secrets را نگه دارید، نسخه‌های بعدی روی هم نصب می‌شوند.

## چیزهایی که نباید انجام دهید

- فایل `kouroshyar-release-key.jks` را داخل ZIP سورس نگذارید.
- رمزها را داخل GitHub عمومی یا داخل workflow ننویسید.
- این فایل و رمزها را برای کسی نفرستید.
- کلید جدید را بعداً عوض نکنید، مگر اینکه عمداً بخواهید نصب روی نسخه قبلی را از دست بدهید.
