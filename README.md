# KumAryk

Мобильное приложение для клиентов грузоперевозок — учёт документов (Путёвка, Дозвол), напоминания об истечении срока и отдельный экран для диспетчера.

Работает в паре с бэкендом на Django: [logidocs-backend](https://github.com/NurikD/logidocs-backend).

## Возможности

- **Клиенту**: список своих документов (или автомобилей, если их несколько), просмотр файлов, баннер с предупреждением об истечении Путёвки и кнопкой «Понятно».
- **Диспетчеру** (тот же admin-аккаунт, отдельный экран по флагу `is_superuser`): список всех клиентов, у которых путёвка истекает или уже просрочена, с ФИО, телефоном и номером машины.
- **Push-уведомления** через Firebase Cloud Messaging.
- **Вход по PIN-коду и биометрии** (отпечаток / Face ID) — как в банковских приложениях: PIN запирает уже сохранённую сессию, повторный логин по паролю не нужен.

## Стек

Flutter 3.x, Dio, flutter_secure_storage, firebase_core/firebase_messaging, local_auth, crypto.

## Настройка

```bash
git clone https://github.com/NurikD/logidocs.git
cd logidocs
flutter pub get
```

**Адрес бэкенда** — `lib/env.dart`:

```dart
const String kBaseUrl = 'https://kumaryk.pythonanywhere.com';
// Локальный бэкенд на том же ПК: http://127.0.0.1:8000
// Локальный бэкенд, эмулятор Android: http://10.0.2.2:8000
```

**Push-уведомления** требуют `google-services.json` (Firebase Android-конфиг) в `android/app/` — файл в `.gitignore`, взять из Firebase Console своего проекта.

## Запуск

```bash
flutter run -d chrome     # веб, без push (нет web-конфига Firebase)
flutter run -d <device>   # физическое Android-устройство
```

## Сборка APK

```bash
flutter build apk --release --target-platform android-arm64
```

Файл: `build/app/outputs/flutter-apk/app-release.apk`.

> Сборка подписана debug-ключом (см. `android/app/build.gradle.kts`) — этого достаточно для установки на свои устройства, но не для Google Play. Перед публикацией в Play Store нужен собственный ключ подписи (`keytool` + `key.properties`).

## Структура проекта

```
lib/
  main.dart   # весь UI: экраны логина/PIN, документы, диспетчер
  api.dart    # HTTP-клиент, работа с токенами, PIN, биометрией
  env.dart    # адрес бэкенда
```
