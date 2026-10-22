#!/usr/bin/env python3
"""Collects the game's text into locale/strings.pot and merges it into each locale/<lang>.po.

    python3 locale/update_po.py          # update the files, list what still needs translating
    python3 locale/update_po.py --check  # only report; exit 1 if any language misses strings

It finds text the way the code shows it: anything inside tr(), tr_n() or Loc.t()/Loc.n(),
sentences in string literals, single words handed straight to a label or button, and
coin names in data/. New strings arrive with an empty translation (the game shows the
English until someone fills it in); strings the code no longer uses are dropped.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGS = ["de", "es", "fr"]
SKIP_DIRS = (".tmp", "tests", "tools", "store", ".godot", ".git", "price-service", "prototype", "art", "audio", "build", "docs", "locale")
PLURAL = {"de": "nplurals=2; plural=(n != 1);", "es": "nplurals=2; plural=(n != 1);", "fr": "nplurals=2; plural=(n > 1);"}

LIT = r'"((?:[^"\\\n]|\\.)*)"'
TR_N = re.compile(r'\b(?:tr_n|Loc\.n)\(\s*' + LIT + r'\s*,\s*' + LIT)
TR = re.compile(r'\b(?:tr|Loc\.t)\(\s*' + LIT + r'\s*\)')
ANY = re.compile(r'(?<![&^\w])' + LIT)
# where a lone word is shown as is: a label or button helper, a .text, a display field in data
SINK = re.compile(r'\.(text|tooltip_text)\s*[=+]|\b(_label|_button|_caption|_heading|_title|_pair|_cell|_row|_menu_button|'
	r'_small_button|_show|_send_after|_upgrade_row|_requirement|_town_button|_row_button|_set_text|_set_cell|_flash)\(')
DATA_KEY = re.compile(r'"(name|title|label|short|tag|text|desc|news|headline|hint|banner|letter|say|after|log|line|shrugged)":\s*' + LIT)
NAME_LISTS = re.compile(r'^\s*const (LEVEL_NAMES|WEEKDAYS|MONTHS|METAL_NAMES|TOOL_NAMES|GRADE_NAMES|KIND_NAMES|STONE_NAMES|SCALING_NAMES|SLIDERS|HEADS|TAGS|SIGMA_READS)\b')
NOT_TEXT = {"Button", "PrimaryButton", "DangerButton", "ToolButton", "BigButton", "Label", "Panel", "PanelContainer",
	"HSlider", "OptionButton", "PopupMenu", "ProgressBar", "Master", "SFX", "XAU", "XAG", "XPT", "XPD", "USD"}


def unescape(s):
	return s.encode("latin-1", "backslashreplace").decode("unicode_escape") if "\\" in s else s


def is_text(s, alone_ok):
	bare = re.sub(r'%[-+0-9.]*[sdfx%]|\{[a-z_]+\}', '', s)
	if not re.search(r'[A-Za-z]{2}', bare) or s in NOT_TEXT:
		return False
	if re.search(r'[A-Za-z]\s+[A-Za-z]', bare):
		return True
	if alone_ok and re.match(r'^[A-Za-z][a-z]+[.!?]$|^[A-Z]+$', s.strip()):
		return True
	return alone_ok and re.match(r'^[A-Z][A-Za-z\'&-]*!?$', s.strip()) is not None


def collect():
	found = {}  # msgid -> (plural or None, set of places)
	def add(msgid, plural, where):
		msgid = unescape(msgid)
		entry = found.setdefault(msgid, [plural and unescape(plural), set()])
		entry[1].add(where)
	for root, dirs, files in os.walk(ROOT):
		rel = os.path.relpath(root, ROOT)
		if rel.split(os.sep)[0] in SKIP_DIRS:
			dirs[:] = []
			continue
		for f in sorted(files):
			path = os.path.join(root, f)
			where = os.path.relpath(path, ROOT)
			if f.endswith(".tres"):
				for m in re.finditer(r'^display_name = ' + LIT, open(path, encoding="utf8").read(), re.M):
					add(m.group(1), None, where)
			if not f.endswith(".gd"):
				continue
			in_list = False
			for line in open(path, encoding="utf8"):
				code = line.split("##")[0]
				if code.lstrip().startswith("#"):
					continue
				for m in TR_N.finditer(code):
					add(m.group(1), m.group(2), where)
				taken = set()
				for m in TR.finditer(code):
					add(m.group(1), None, where)
					taken.add(m.group(1))
				in_list = in_list or bool(NAME_LISTS.match(code))
				# a row of a table built in code: ["weight", "Weight", ...]
				alone = bool(SINK.search(code)) or in_list or re.search(r'\[\s*"[^"]*",\s*"[A-Z]', code) is not None
				keyed = {m.group(2) for m in DATA_KEY.finditer(code)}
				keyed_words = {m.group(2) for m in DATA_KEY.finditer(code) if m.group(1) != "line"}  # line is an id
				plural_parts = {s for m in TR_N.finditer(code) for s in m.groups()}
				for m in ANY.finditer(code):
					s = m.group(1)
					if s in taken or s in plural_parts:
						continue
					listed = in_list and re.match(r'^[a-z][a-z -]*$', s) and not code[m.end():].lstrip().startswith(":")
					# lower-case words shown as is: a data field ("short": "lunch") or a lookup inside tr({...})
					listed = listed or ((s in keyed_words or "tr({" in code) and re.match(r'^[a-z][a-z -]+$', s) and not code[m.end():].lstrip().startswith(":"))
					if is_text(s, alone or s in keyed) or listed:
						add(s, None, where)
				if in_list and ("]" in code or "}" in code):
					in_list = False
	return found


def po_quote(s):
	s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")
	return '"%s"' % s


def po_unquote(s):
	out, i = "", 0
	s = s.strip()[1:-1]
	while i < len(s):
		c = s[i]
		if c == "\\" and i + 1 < len(s):
			out += {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(s[i + 1], s[i + 1])
			i += 2
		else:
			out += c
			i += 1
	return out


def read_po(path):
	"""msgid -> {"plural": str|None, "str": [msgstr...]}"""
	entries, cur, field = {}, None, None
	if not os.path.exists(path):
		return entries
	def flush():
		if cur and cur.get("id"):
			entries[cur["id"]] = cur
	for line in open(path, encoding="utf8"):
		line = line.rstrip("\n")
		if line.startswith("msgid "):
			flush()
			cur, field = {"id": po_unquote(line[6:]), "plural": None, "str": {}}, "id"
		elif line.startswith("msgid_plural "):
			cur["plural"], field = po_unquote(line[13:]), "plural"
		elif line.startswith("msgstr["):
			n = int(line[7:line.index("]")])
			cur["str"][n], field = po_unquote(line[line.index("]") + 2:]), n
		elif line.startswith("msgstr "):
			cur["str"][0], field = po_unquote(line[7:]), 0
		elif line.startswith('"') and cur is not None:
			if field == "id":
				cur["id"] += po_unquote(line)
			elif field == "plural":
				cur["plural"] += po_unquote(line)
			else:
				cur["str"][field] = cur["str"].get(field, "") + po_unquote(line)
	flush()
	return entries


def write_po(path, lang, found, old):
	out = ['msgid ""', 'msgstr ""', '"Content-Type: text/plain; charset=UTF-8\\n"']
	if lang:
		out += ['"Language: %s\\n"' % lang, '"Plural-Forms: %s\\n"' % PLURAL[lang]]
	out.append("")
	missing = 0
	for msgid in sorted(found, key=lambda k: (sorted(found[k][1])[0], k)):
		plural, places = found[msgid]
		out.append("#: " + " ".join(sorted(places)))
		out.append("msgid " + po_quote(msgid))
		have = old.get(msgid, {}).get("str", {}) if lang else {}
		if plural:
			out.append("msgid_plural " + po_quote(plural))
			for n in range(2):
				out.append("msgstr[%d] %s" % (n, po_quote(have.get(n, ""))))
			missing += 0 if lang and all(have.get(n) for n in range(2)) else 1
		else:
			out.append("msgstr " + po_quote(have.get(0, "")))
			missing += 0 if lang and have.get(0) else 1
		out.append("")
	text = "\n".join(out)
	if not CHECK:
		open(path, "w", encoding="utf8").write(text)
	return missing


CHECK = "--check" in sys.argv
if __name__ == "__main__":
	found = collect()
	write_po(os.path.join(ROOT, "locale", "strings.pot"), None, found, {})
	bad = False
	for lang in LANGS:
		path = os.path.join(ROOT, "locale", lang + ".po")
		missing = write_po(path, lang, found, read_po(path))
		print("%s: %d of %d strings still need translating" % (lang, missing, len(found)))
		bad = bad or missing > 0
	sys.exit(1 if CHECK and bad else 0)
