# Translations

The game ships in English, German (`de.po`), Spanish (`es.po`) and French (`fr.po`). The
player picks a language in Settings; "Auto" follows the device. Godot loads the `.po` files
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

Then refresh the string list and the three `.po` files:

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

`tests/smoke_test.tscn` checks that every string is translated, keeps its format slots and
uses only letters the font has. To play a bug bot in another language:
`tests/run_bug_bots.sh 4 5 --lang=de`.
