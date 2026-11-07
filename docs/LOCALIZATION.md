# Languages and update notices

The plugin follows the display language selected in Omarchy, including changes
made while the shell is running. It reads `$XDG_CONFIG_HOME/omarchy/language`
(or `~/.config/omarchy/language`). `OMARCHY_LANGUAGE_FILE` overrides this path,
matching Omarchy's own test override. When no supported choice is present, it
uses `LC_ALL`, then `LC_MESSAGES`, then `LANG`, with English as the final fallback.
Regional variants are preserved: `pt-BR`, `pt`, `zh-CN`, `zh-TW`, and `es-MX`.
Arabic, Persian, Hebrew and Urdu use right-to-left UI layouts.

All 50 languages/variants in the Omarchy registry snapshot are shipped locally
in `js/locales/`. Translation never makes a network request. Catalogs were
machine-translated; common French UI terminology was corrected manually.
Native-speaker review is welcome, particularly for technical diagnostics.
File names, URLs, commands, shortcut names and API identifiers are never translated.
Existing transient errors keep the language in which they were generated;
new messages and bound UI labels use the current language.

To maintain translations, keep the English message as the `L10n.t()` key and
use `%1`, `%2`, etc. for values, passed in an argument array. Do not concatenate
translated words to form new sentences. Preserve each message's placeholders
in every catalog. Run the localization tests after editing catalogs. The registry
snapshot comes from Omarchy's `default/i18n/locales.json` (50 entries).

## Update notices

The plugin checks the public GitHub latest-release endpoint when loaded and
at most once every 24 hours. The check is shared across monitors and cached
across restarts. It sends no account credentials, server address, file names,
window titles or captured pixels. Only published stable `major.minor.patch`
releases newer than the installed manifest version are announced.

A desktop notification is shown once per available release when `notify-send`
is available. A colored dot and a translated tooltip with the native update
command remain visible in the bar until the plugin is updated, including when
desktop notifications are unavailable or transfer notifications are disabled.
No update is installed automatically. The `checkUpdates` widget setting (shown as
“Check for plugin updates” in Omarchy’s widget settings) disables background
release checks and their indicator when turned off. The notification cache lives at
`$XDG_STATE_HOME/<plugin-id>/update.json` (default `~/.local/state/`).
The helper uses Python 3's standard library; notifications use optional libnotify.
Offline or rate-limited checks fail quietly and retry the next day.

## Checks

Run `python3 scripts/test_localization.py` and
`python3 scripts/test_updates.py` for the portable checks.
`python3 scripts/test_localization_runtime.py` switches all 50 languages
inside an isolated Quickshell process; it does not change the desktop language.
