# Translations

The game ships in English, German (`de.po`), Spanish (`es.po`), French (`fr.po`) and
Chinese in three forms: Simplified (`zh_CN.po`, setting code `zh`, Mandarin for the mainland),
Traditional (`zh_TW.po`, Mandarin for Taiwan) and Cantonese (`zh_HK.po`, Traditional for Hong
Kong, with customers and story characters speaking Cantonese). The player picks a language in Settings;
"Auto" follows the device. Godot loads the `.po` files
listed under `[internationalization]` in `project.godot`; there is no import step.

## Adding text to the game

- A Label or Button whose text is a plain literal translates itself, and switches live
  when the language changes: `label.text = "Open the shop"`.
- Text built with `%` or `.format()` must be translated first, then filled in:
  `tr("Day %d") % day`. In a static function, which can't call `tr()`, use `Loc.t(...)`.
- Counts use plurals instead of `"" if n == 1 else "s"`:
  `tr_n("%d customer", "%d customers", n) % n` (or `Loc.n(...)` in a static function).
- Names stored in data (upgrades, events, customer lines) stay English in the data and are
  translated where they are shown: `tr(upgrade.name)`. Compare and match on the English,
  never on translated text (for weekdays, use `Day.weekday_key()` for logic).
- Lower-case a word before translating it, not after: `tr(role.title.to_lower())`, since
  German capitalises nouns.

Then refresh the string list and every `.po` file:

    python3 locale/update_po.py           # writes strings.pot, adds new strings to each .po
    python3 locale/update_po.py --check   # exits 1 while any string is untranslated

New strings appear in each `.po` with an empty `msgstr`, which shows the English until
someone fills it in.

## Rules for translators

- Keep every `%d`, `%s`, `%.1f` and `%%` in the same order as the English (GDScript can't
  reorder them). `{name}` slots may move.
- Buttons are narrow. Keep button words about as long as the English.
- Only letters the pixel font draws: plain ASCII plus the accented letters in
  `art/pixel_font.gd` (`ACCENTED`). Use plain `"` for quotes.
- `zh_TW` and `zh_HK` started as conversions of `zh_CN` (OpenCC `s2twp` and `s2hk`), so a
  fix to a Chinese string usually belongs in all three. Spoken lines in `zh_HK` are
  Cantonese (嘅, 咗, 唔); menus and help text are standard written Chinese.
- Chinese uses full-width punctuation (，。：！？（）) and plain `"` for quotes. People's and
  shops' names stay in English (the game shows most of them untranslated), and so does the
  game's title.

## Chinese characters

The pixel font only has the characters the game uses. They are baked from Fusion Pixel 8px
(`locale/fonts`, SIL Open Font License, see `OFL.txt`) into `art/cjk_glyphs.gd`; characters
only the Traditional files use come from its Traditional cut. After changing a Chinese `.po`, or putting Chinese anywhere in a script, rebake them:

    pip install fonttools brotli pillow
    python3 locale/make_cjk_glyphs.py

The smoke test fails on any character the font can't draw, so a missed rebake shows up there.

`tests/smoke_test.tscn` checks that every string is translated, keeps its format slots and
uses only letters the font has. To play a bug bot in another language:
`tests/run_bug_bots.sh 4 5 --lang=de` (or `es`, `fr`, `zh`, `zh_TW`, `zh_HK`).
