# CamScan: ресерч и план развития

Дата: октябрь 2026. Платформа: iOS 26+ (SwiftUI, SwiftData, VisionKit), как в текущем MVP.

## 1. Рынок и почему есть ниша

**CamScanner** — главный игрок, его стабильно ругают за одно и то же:
- реклама в бесплатной версии, включая видео между сканами;
- водяной знак на экспортированных PDF;
- OCR только по подписке (~$4.99/мес или ~$50/год);
- триалы на 3 дня, которые сами превращаются в годовую подписку, — основная масса жалоб в 2025–2026;
- осадок по приватности после истории 2019 года с вредоносным рекламным SDK.

**Что происходит с конкурентами:**
| Приложение | Модель | Заметки |
|---|---|---|
| Adobe Scan | freemium | хороший OCR, тянет в экосистему Adobe и облако |
| Microsoft Lens | **закрыт** | убран из сторов в феврале 2026, новые сканы перестали работать 9 марта 2026. Microsoft отправляет пользователей в OneDrive, а там сканы только в облаке. Освободилась аудитория тех, кто хочет «бесплатно и без мусора» |
| Genius Scan, Scanner Pro, SwiftScan | подписка | качественные, но тоже на подписке |
| Apple Notes / Files | бесплатно | сканер встроен, но нет менеджмента документов, нормального экспорта, подписи, сжатия и т.д. |
| QuickScan и мелкие инди-приложения | бесплатно / без рекламы | функций мало |

**Вывод — позиционирование:** «Сканер, который не бесит». Без рекламы, без водяных знаков, без подписок-ловушек, всё обрабатывается на устройстве, данные никуда не уходят. Монетизация — **разовая покупка Pro** (уже так и сделано, $4.99 non-consumable). Это и есть главное отличие, его стоит вынести в название и скриншоты в App Store.

## 2. Что уже есть в MVP

- Скан через `VNDocumentCameraViewController`: поиск краёв, исправление перспективы, многостраничность — из коробки.
- Хранение в SwiftData (`ScannedDocument` → `ScannedPage`).
- 5 фильтров на CoreImage.
- OCR через Vision (`VNRecognizeTextRequest`, en/ru), поиск по распознанному тексту.
- Экспорт в PDF (`UIGraphicsPDFRenderer`) и шаринг.
- StoreKit 2: разовая покупка Pro, лимит 3 скана в день во free.

## 3. Проблемы в текущем коде (стоит починить в первую очередь)

1. **Нет `NSCameraUsageDescription`** в настройках таргета (`INFOPLIST_KEY_NSCameraUsageDescription` в `project.pbxproj`). На реальном устройстве приложение упадёт при первом же скане, и ревью App Store такое не пропустит.
2. **PDF без текстового слоя.** `PDFService` рисует только картинки, так что в экспортированном PDF нельзя искать и выделять текст. У конкурентов «searchable PDF» — базовая функция. Решение: поверх картинки рисовать невидимый текст по `boundingBox` из `VNRecognizedTextObservation` (Core Text с прозрачной заливкой или `PDFAnnotation`).
3. **Размер страницы зашит как US Letter (612×792).** Для РФ/ЕС нужен A4 (595×842). Нужна настройка: A4 / Letter / «по размеру скана».
4. **Картинки лежат прямо в базе.** `imageData` без `@Attribute(.externalStorage)` раздувает SwiftData-хранилище, и список тормозит: `thumbnail` декодирует полный JPEG на каждую строку. Нужны `.externalStorage` и отдельная маленькая миниатюра.
5. **Фильтры портят оригинал.** `PageFilterView` перезаписывает `imageData`, откатиться нельзя, а фильтры накладываются друг на друга. Лучше хранить оригинал и `filter`/параметры, а результат рендерить (или кэшировать).
6. **Фильтры слабые для документов.** `colorMonochrome` — не «Ч/Б документ». Нужен нормальный B&W: в CoreImage есть `CIDocumentEnhancer`, плюс adaptive threshold и режим «magic color» (выбелить фон, сохранить цветные печати и подписи).
7. **Гонка в фильтрах.** Каждое нажатие запускает `Task.detached`, и при быстрых нажатиях результат старого фильтра может прийти последним. Нужно отменять предыдущую задачу.
8. **OCR закрыт пейволом.** Vision работает на устройстве и бесплатно, Apple Notes даёт это даром. Прятать OCR за оплату — тот же паттерн, за который ругают CamScanner. Лимит «3 скана в день» тоже ощущается как ограничение в стиле CamScanner. См. раздел 5.
9. **Языки OCR зашиты** (`["en", "ru"]`). Лучше `automaticallyDetectsLanguage = true` или выбор языка в настройках. А для iOS 26 — перейти на новый API (раздел 4).
10. **Имя PDF берётся из заголовка как есть.** Символ `/` в названии сломает запись файла, нужна санитизация.
11. **Pro-статус хранится в `UserDefaults`**, и его легко подменить. Для разовой покупки это терпимо, но источником правды должны быть `Transaction.currentEntitlements`, без кэша.
12. Тестов нет — только заглушка в `CamScanTests`.

## 4. Возможности платформы (iOS 26), которые стоит использовать

Всё перечисленное работает **на устройстве, без серверов** — это совпадает с позиционированием «приватно».

| Задача | API |
|---|---|
| Скан с камеры | `VNDocumentCameraViewController` (уже используется) |
| Импорт фото/PDF из Галереи и Файлов | `PhotosPicker`, `fileImporter`; поиск границ документа на фото: `VNDetectDocumentSegmentationRequest` / `DetectDocumentSegmentationRequest` + `CIPerspectiveCorrection` |
| **Структура документа: таблицы, списки, абзацы, штрихкоды** | `RecognizeDocumentsRequest` (новое в iOS 26) → `DocumentObservation` с контейнерами `paragraphs/tables/lists/barcodes`. Даёт экспорт таблиц в CSV/Excel, а это киллер-фича для чеков и счетов |
| OCR текста | `RecognizeTextRequest` (Swift-native Vision API) |
| Данные из текста (телефоны, даты, адреса, ссылки) | `NSDataDetector` / детекторы в `RecognizeDocumentsRequest` |
| Резюме, авто-название, теги, «что это за документ» | Foundation Models framework (on-device LLM, iOS 26, устройства с Apple Intelligence) |
| Живой текст и выделение на картинке | `ImageAnalysisInteraction` (VisionKit Live Text) |
| Редактирование PDF, аннотации, подпись | PDFKit (`PDFView`, `PDFAnnotation`) + PencilKit для рисования подписи |
| Пароль на PDF | `PDFDocument.write(to:withOptions:)` с `.userPasswordOption` / `.ownerPasswordOption` |
| Блокировка приложения | LocalAuthentication (Face ID) |
| Синхронизация | SwiftData + CloudKit (приватная база iCloud пользователя — без своего бэкенда). Нужны дефолты/optional у всех полей и никаких `.unique` |
| Поиск из системы | Core Spotlight — индексировать OCR-текст |
| Shortcuts / Siri / кнопка действия | App Intents («Отсканировать в CamScan», «Найти документ») |
| Сканирование из других приложений | Share Extension, Action Extension |
| Виджет / Control Center | WidgetKit + ControlWidget «Быстрый скан» |

## 5. Функции и роадмап

### v1.0 — «честный сканер» (минимум для релиза)
- [x] Починить пункты 1–7 из раздела 3 (+ пейвол: сканы и OCR бесплатны, без лимита).
- [x] **Searchable PDF** (текстовый слой).
- [x] Размер страницы A4/Letter/«по скану» с подгонкой скана под лист.
- [ ] Качество/сжатие (S/M/L с примерным размером файла).
- [x] Импорт из Фото с автоматическим поиском документа и обрезкой.
- [x] Импорт из Файлов (PDF/картинки).
- [x] Редактор страницы: ручная обрезка по 4 углам + авто, поворот, сброс (неразрушающие правки).
- [x] Переставить, удалить страницы, добавить страницы в существующий документ.
- [x] Фильтры с выравниванием освещения (убирают тени): Auto, Magic Color, Grayscale, B&W, Original + яркость/контраст.
- [ ] Экспорт: PDF, JPEG, PNG, текст (.txt); поделиться / сохранить в Файлы.
- [ ] Папки/теги, сортировка, поиск по OCR.
- [x] Face ID на открытие приложения (Pro).
- [ ] Онбординг из одного экрана: «без рекламы, без водяных знаков, всё на устройстве».

### v1.1 — работа с PDF
- [x] Подпись (нарисовать один раз и сохранить, потом вставлять в любой документ).
- [x] Рисование и маркер (PencilKit).
- [ ] Текстовые аннотации.
- [x] Объединить документы, вынести страницы в новый документ.
- [x] Пароль на PDF.
- [ ] Заполнение PDF-форм (`PDFAnnotation` с виджетами).
- [ ] Скрытие (redaction) — именно удаление пикселей и текста, а не чёрный прямоугольник поверх.

### v1.2 — «умные» функции на устройстве
- [x] `RecognizeDocumentsRequest`: экспорт таблиц в CSV.
- [ ] Экспорт таблиц в XLSX.
- [ ] Режимы сканирования: документ, чек, визитка (→ контакт), удостоверение (две стороны на одну страницу), книга (разворот → две страницы), доска/whiteboard.
- [ ] Авто-название и авто-теги через Foundation Models («Счёт ЖКХ, сентябрь 2026»).
- [ ] Короткое резюме документа, вопросы к документу (Foundation Models, on-device).
- [ ] QR-коды и штрихкоды на странице.
- [ ] Spotlight, App Intents, виджет, Share Extension.

### v2 — по желанию
- [ ] Синхронизация через iCloud (CloudKit).
- [ ] macOS-версия (SwiftUI/Catalyst), iPad с Apple Pencil.
- [ ] Перевод текста (Translation framework, on-device).
- [ ] Автосохранение в выбранную папку Files/iCloud Drive.

## 6. Монетизация

Главное отличие от CamScanner — **никаких подписок и рекламы**. Предлагаемое разделение:

**Бесплатно, без ограничений по количеству:**
скан, импорт, фильтры, обрезка, OCR, searchable PDF, экспорт без водяного знака, папки, поиск.

**Pro — разовая покупка ($4.99–9.99), Family Sharing включить:**
подпись, аннотации, merge/split, пароль на PDF, redaction, экспорт таблиц, «умные» функции на Foundation Models, Face ID-блокировка, iCloud-синхронизация, кастомные иконки приложения.

Почему так: бесплатная часть сама становится маркетингом («наконец нормальный бесплатный сканер»), а в Pro — то, что нужно тем, кто работает с документами регулярно. Лимит «3 скана в день» лучше убрать: скан — базовая функция, и лимит на неё вызывает то же раздражение, что и CamScanner.

Опционально: tip jar (consumable-«донаты») и/или будущий апгрейд-SKU для v2, если появятся затратные функции.

## 7. Приватность (то, что стоит обещать и выполнять)

- Никакой аналитики и рекламных SDK. App Privacy в App Store — «Data Not Collected». Это видно прямо на странице приложения и сильно отличает от конкурентов.
- Вся обработка на устройстве (Vision, Foundation Models, CoreImage).
- Если будет синхронизация — только приватная база iCloud пользователя, без своего сервера.
- Файлы защищены через `FileProtectionType.complete`.

## 8. Ближайшие шаги

1. Хотфикс: `NSCameraUsageDescription`, `.externalStorage`, санитизация имени файла.
2. Searchable PDF и выбор размера страницы.
3. Недеструктивные фильтры + `CIDocumentEnhancer`.
4. Пересмотреть пейвол (OCR и сканы бесплатно, Pro — PDF-инструменты).
5. Импорт из Фото и Файлов, редактор страниц.
6. Юнит-тесты на `PDFService` (кол-во страниц, наличие текста через `PDFDocument.string`), `ScanLimitService` / логику Pro, санитизацию имени файла.

## Источники

- [Microsoft Lens retirement — Microsoft Support](https://support.microsoft.com/en-us/lens/)
- [Microsoft Lens has been retired — Neowin](https://www.neowin.net/news/microsoft-lens-has-been-retired/)
- [CamScanner reviews — Capterra](https://www.capterra.com/p/210426/CamScanner/reviews/)
- [CamScanner complaints — Şikayetvar](https://www.sikayetvar.com/en/camscanner-us)
- [Scanner apps ranked by complaints, 2026 — unstar.app](https://unstar.app/blog/adobe-scan-camscanner-microsoft-lens-genius-scan-swiftscan-pdf-scanner-apps-ranked-2026)
- [CamScanner alternatives — AlternativeTo](https://alternativeto.net/software/camscanner/?p=2)
- [RecognizeDocumentsRequest — Apple Developer](https://developer.apple.com/documentation/vision/recognizedocumentsrequest)
- [Recognizing tables within a document — Apple Developer](https://developer.apple.com/documentation/vision/recognize-tables-within-a-document)
