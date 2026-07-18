# تنظیم منبع تعطیلات نسخه 3.6.53

## اصل طراحی

تقویم و همه اطلاعات کاربر آفلاین باقی می‌مانند. برنامه فقط با درخواست `GET` یک فایل کوچک تعطیلات را از نشانی HTTPS دریافت می‌کند. هیچ پرونده، نام، مدرک، تاریخ شخصی یا شناسه‌ای از داده‌های برنامه به منبع ارسال نمی‌شود.

به‌روزرسانی به‌صورت پیش‌فرض خاموش است. فایل دریافتی فقط وقتی پذیرفته می‌شود که امضای Ed25519 آن با کلید عمومی قرارگرفته در APK معتبر باشد.

## GitHub Variables لازم

در Repository Settings > Secrets and variables > Actions > Variables این دو متغیر تنظیم شوند:

- `KOUROSHYAR_HOLIDAY_FEED_URL`: نشانی مستقیم HTTPS فایل envelope امضاشده
- `KOUROSHYAR_HOLIDAY_PUBLIC_KEY`: کلید عمومی Ed25519 خام 32 بایتی با Base64

این دو مقدار Secret امضای APK نیستند. کلید خصوصی تعطیلات نباید داخل سورس، ZIP، GitHub Variables یا APK قرار گیرد.

## ساخت کلید تعطیلات

نمونه با OpenSSL:

```bash
openssl genpkey -algorithm ED25519 -out holiday_feed_private.pem
openssl pkey -in holiday_feed_private.pem -pubout -out holiday_feed_public.pem
```

برای ساخت envelope و استخراج Base64 کلید عمومی خام می‌توان از ابزار زیر استفاده کرد:

```bash
python tools/sign_holiday_feed.py \
  holiday_feed/payload.json \
  /path/outside/source/holiday_feed_private.pem \
  holiday_feed/holidays.json \
  --public-key-output /tmp/holiday_public_key_base64.txt
```

فایل `holiday_feed_private.pem` باید خارج از سورس نگهداری شود.

## قواعد داده

- `revision` با هر انتشار افزایش یابد.
- فقط اطلاعیه دارای منبع رسمی وارد شود.
- تعطیلی لغوشده با همان `id` و `status: cancelled` منتشر شود.
- نوع‌های مجاز: `official`، `national_emergency`، `provincial`، `administrative` و `judiciary`.
- محدوده‌های مجاز: `national`، `province` و `organization`.
- رکورد `organization` فقط برای نگهداری جزئیات اطلاعیه پذیرفته می‌شود و تا زمانی که برنامه فیلتر دستگاه مشخص ندارد، روز را برای کل استان تعطیل علامت نمی‌زند.
- تاریخ با قالب شمسی `YYYY-MM-DD` ثبت شود.
- `sourceUrl` باید HTTPS و مربوط به اطلاعیه رسمی باشد.

## اثر بر مهلت‌ها

داده آنلاین هیچ کار، مهلت یا جلسه‌ای را جابه‌جا یا ویرایش نمی‌کند. اگر روز سررسید مهلت پرونده تعطیل باشد، برنامه فقط هشدار بررسی وضعیت مرجع قضایی را نمایش می‌دهد.
