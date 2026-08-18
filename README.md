# TG WS Proxy для iOS

Нативное iOS-приложение для запуска Telegram WebSocket прокси, полностью переписанное с Python на **Swift** и **SwiftUI** с дизайном **Liquid Glass**.

## Возможности

- 🚀 Запуск и остановка MTProto WebSocket-прокси одним нажатием
- 🎨 Современный интерфейс в стиле **liquid glass** (стеклянные карточки, размытие, мягкие тени)
- 📑 Три вкладки: **Прокси**, **Настройки**, **Логи**
- ⚙️ Настройка хоста, порта, secret, fake-TLS домена и режимов
- 📋 Просмотр логов в реальном времени с фильтрацией по уровню
- 📱 Полная поддержка iOS 15+
- 🔗 Быстрое копирование ссылки подключения и переход в Telegram

## Вкладки

### Прокси
- Логотип Telegram в качестве центрального элемента
- Статус прокси (запущен / остановлен)
- Кнопка запуска/остановки
- Живая статистика (активные соединения, трафик, WebSocket)
- Копирование и переход по `tg://proxy` ссылке

### Настройки
- Хост и порт
- Secret key
- Fake TLS домен
- Переключение режимов (CF fallback, Proxy Protocol, Force test DC)

### Логи
- Просмотр событий в реальном времени
- Фильтрация по уровню (Info, Warning, Error)
- Автоматическая прокрутка
- Очистка логов

## Как это работает

```
Telegram iOS → Локальный MTProto (127.0.0.1:1443) → TG WS Proxy → WSS (kws{dc}.web.telegram.org) → Telegram DC
```

1. Приложение поднимает локальный MTProto-прокси через `Network.framework` (`NWListener`).
2. Принимает соединение и читает obfuscation2 handshake (AES-256-CTR).
3. Проверяет secret и извлекает `DC ID` из исходного пакета.
4. Устанавливает защищённое WebSocket-соединение с нужным датацентром Telegram.
5. Прозрачно мостит трафик с двусторонней пере-шифровкой и разбиением MTProto-пакетов на WS-фреймы.
6. При недоступности WebSocket использует TCP fallback напрямую к датацентру.

## Структура проекта

```
TGWSProxy.xcodeproj/          # Xcode проект
TGWSProxy/
├── TGWSProxyApp.swift        # Точка входа (@main)
├── Info.plist                # Конфигурация приложения
├── Models/
│   ├── AppState.swift        # Общее состояние приложения
│   ├── ProxySettings.swift   # Настройки прокси (host, port, secret)
│   ├── LogEntry.swift        # Модель лога + LogStore
│   └── ProxyManager.swift    # Координатор запуска/остановки
├── Networking/
│   ├── ProxyEngine.swift     # TCP-слушатель и управление соединениями
│   ├── ClientConnection.swift# Мост клиент ↔ Telegram
│   └── WebSocketClient.swift # Клиент WebSocket на Network.framework
├── Crypto/
│   ├── AESCipher.swift       # AES-256-CTR обёртка (CommonCrypto)
│   ├── MTProtoConstants.swift# Константы протокола
│   ├── CryptoContext.swift   # 4 крипто-состояния моста
│   ├── Handshake.swift       # Генерация и проверка handshake
│   ├── MsgSplitter.swift     # Разбиение на MTProto-пакеты
│   └── FakeTLS.swift         # TLS-маскировка
└── Views/
    ├── GlassBackground.swift # Фон с градиентом и GlassCard
    ├── ContentView.swift     # Главный экран с вкладками
    ├── ProxyTabView.swift    # Вкладка «Прокси»
    ├── SettingsTabView.swift # Вкладка «Настройки»
    └── LogsTabView.swift     # Вкладка «Логи»
```

## Требования

- iOS 15.0 или выше
- Xcode 14.0 или выше
- Swift 5.7+

## Установка

1. Клонируйте репозиторий
```bash
git clone https://github.com/Werhes/tg-ws-proxy-ios.git
cd tg-ws-proxy-ios
```

2. Откройте проект в Xcode
```bash
open TGWSProxy.xcodeproj
```

3. Выберите целевое устройство и нажмите Run (⌘R)

> **Фоновый режим:** приложение использует фоновый режим `audio` с бесшумным аудио-циклом, чтобы прокси продолжал работать, когда приложение свёрнуто или заблокирован экран. Этот метод подходит для установки через AltStore/Sideloadly. Для публикации в App Store корректным решением является Network Extension (VPN) — потребуются соответствующие entitlements и платный аккаунт разработчика.

## Автосборка и релиз (GitHub Actions)

В репозитории настроен CI-воркфлоу [`.github/workflows/build.yml`](.github/workflows/build.yml):

- **Проверка сборки** — при каждом push в `main` и PR приложение собирается для симулятора iOS (без подписи), чтобы убедиться, что код компилируется.
- **Релиз** — при создании тега `v*` (например `v1.0.0`) или ручном запуске воркфлоу с `make_release` автоматически:
  1. Собирается Release-архив для устройства.
  2. Создаётся `.ipa` (без подписи, для AltStore/Sideloadly/jailbreak).
  3. Создаётся **GitHub Release** с прикреплённым `.ipa`.

### Подписанный релиз (App Store / TestFlight)

Для подписанной сборки задайте **секреты** в настройках репозитория (`Settings → Secrets and variables → Actions`):

| Secret | Назначение |
|--------|-----------|
| `APPLE_CERT_P12` | Дистрибутивный сертификат (base64) |
| `APPLE_CERT_PASSWORD` | Пароль сертификата |
| `APPLE_PROVISIONING_PROFILE` | Provisioning profile (base64) |
| `APPLE_TEAM_ID` | Team ID из Apple Developer |

Если эти секреты заданы, воркфлоу дополнительно соберёт подписанный `.ipa` и прикрепит его к релизу.

### Bundle ID
Идентификатор пакета приложения — **`com.werhes.tgws`** (задан в `TGWSProxy.xcodeproj/project.pbxproj`).

## Лицензия

MIT License — см. файл LICENSE

## Благодарности

Основано на проекте [tg-ws-proxy](https://github.com/Flowseal/tg-ws-proxy)
