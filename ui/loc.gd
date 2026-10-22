class_name Loc
extends RefCounted
## Translation helpers for static functions, which can't call tr(). Instance code uses tr()
## and tr_n() as usual; Labels and Buttons translate plain text on their own.
## The translations live in locale/<language>.po (see locale/README.md).


static func t(text: String) -> String:
	return String(TranslationServer.translate(text))


## "%d day" / "%d days" style plurals: the plural rule of the current language picks the form.
static func n(singular: String, plural: String, count: int) -> String:
	return String(TranslationServer.translate_plural(singular, plural, count))
