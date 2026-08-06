# CLAUDE.md — IvanLutsenko.github.io

Личный сайт-портфолио (спикер, Android Tech Lead). Чистая статика, без сборки.

## Деплой и домен ⚠️ (главная пастка)

- Боевой домен: **https://ivan.nullptr.party** (custom domain).
- Дефолтный github.io-адрес **НЕ работает**: `ivanlutsenko.github.io` → 404. Репозиторий лежит под организацией `nullptr-party` (`github.com/nullptr-party/IvanLutsenko.github.io`), и default Pages URL был бы `nullptr-party.github.io/...`, а не `ivanlutsenko.github.io`.
- **Все абсолютные URL** (`og:image`, `og:url`, `twitter:image`, `canonical`, JSON-LD `url`/`image`) обязаны указывать на `https://ivan.nullptr.party`, иначе картинки/превью отдают 404 и в соцсетях не показываются.
- CNAME-файла в репо нет — домен настроен в GitHub Pages settings (не удивляйся отсутствию CNAME).
- Деплой: push в `master` → GitHub Pages подхватывает за 1–2 мин. Проверять изменения на ivan.nullptr.party.
- Telegram/соцсети агрессивно кешируют OG-превью. Принудительно обновить — прогнать ссылку через `@WebpageBot` в Telegram.

## Структура

- `index.html` — вся главная страница: разметка + CSS (`<style>`) + JS (`<script>`) инлайном. Внешних css/js нет, билда нет — правится напрямую.
- `plugins.html` — подстраница про маркетплейс `awac-ai-agent-plugins`, устроена так же (инлайн CSS/JS, три языка).
- `res/` — ассеты: картинки, PDF, шрифты и **самодостаточные презентации** (`ci-cd-lovestory*.html`, `crashlytics-talk.html`, `beetech-2026-pitch.html`) — каждая отдельный HTML-файл.
- В корне — favicon-набор, `site.webmanifest`.

## Версии плагинов на `plugins.html` — генерируются ⚠️

- Теги `tag-ver` и `tag-target` помечены `data-plugin="<id>"` и **правятся скриптом, не руками**: `scripts/sync-plugins.py` читает `.claude-plugin/marketplace.json` и `.agents/plugins/marketplace.json` из репы плагинов и переписывает их. Ручная правка переживёт до первого прогона.
- Прогоняет `.github/workflows/sync-plugins.yml`: по расписанию, по `workflow_dispatch` и на пуш в `master`. Коммитит от `github-actions[bot]` встроенным `GITHUB_TOKEN` — секретов и PAT не нужно, поэтому экшен и живёт здесь, а не в репе плагинов.
- Источник правды — **опубликованный** манифест на GitHub. Пока релиз плагина не запушен, сайт честно показывает старую версию.
- Всё остальное на странице — рукописная проза на трёх языках, скрипт её не трогает, а **проверяет**: появился плагин в манифесте или разошлось число «восемь» — прогон падает, карточку и текст заводить руками.
- Локально: `python3 scripts/sync-plugins.py --check` (только проверка) или `--local ../awac-ai-agent-plugins` (без сети).

## Трёхъязычность (en / uk / ru)

- Контент дублируется на 3 языках через атрибут `data-lang="en|uk|ru"`. Активный язык помечается классом `.active`; правило `[data-lang]:not(.active){display:none !important}` скрывает остальные.
- Переключатель — JS внизу `index.html`: хранит выбор в `localStorage` (`preferredLanguage`), дефолт `en`, обновляет `<html lang>`.
- **Добавляя любой текст — давай сразу все 3 языка** (en идёт первым и с `class="active"`). Иначе на части языков блок будет пустым.

## Галерея видео

- Карточка: `<div class="video-placeholder" data-video-id="<ID>" role="button" tabindex="0" aria-label="...">` с превью как `background-image` (`https://img.youtube.com/vi/<ID>/maxresdefault.jpg`).
- JS лениво подменяет плейсхолдер на `<iframe>` по клику и по Enter/Space (карточки доступны с клавиатуры).
- Новое видео = новая `.video-card` по образцу существующих + три языка + `aria-label`. Проверь, что превью отдаётся 200 (`maxresdefault.jpg`).

## Git / коммиты

- Личный репозиторий → сообщения свободные, imperative mood, English. Без AI-атрибуции (см. `~/CLAUDE.md`).
- `.claude/` не коммитить (в `.gitignore`).
- Коммитить и пушить только по явной просьбе.
