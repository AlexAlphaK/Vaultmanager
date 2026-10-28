#!/usr/bin/env python3
"""Builds data/price_history.gd, the monthly metal prices the Market replays.

Sources (both free to bundle in a commercial game):
  * Gold, silver, platinum: World Bank Commodity Price Data (The Pink Sheet), monthly
    averages in USD per troy ounce, licensed CC BY 4.0. Download
    CMO-Historical-Data-Monthly.xlsx from https://www.worldbank.org/en/research/commodity-markets
  * Palladium: U.S. Geological Survey annual average prices (Mineral Commodity Summaries
    and Minerals Yearbook, public domain), in PALLADIUM_YEARLY below. The Pink Sheet has
    no palladium, so months are shaped by platinum's moves around those yearly averages,
    and outside 1991-2025 palladium follows platinum at the nearest year's ratio.

Usage: python3 tools/prices/build_history.py CMO-Historical-Data-Monthly.xlsx
"""
import math
import sys

import openpyxl

FIRST_YEAR = 1972  # gold has floated freely since the end of Bretton Woods
OUT = "data/price_history.gd"

# USGS annual average palladium price, USD per troy ounce (2025 is USGS's estimate).
PALLADIUM_YEARLY = {
    1991: 89.06, 1992: 89.07, 1993: 122.97, 1994: 144.15, 1995: 153.35, 1996: 130.39,
    1997: 184.14, 1998: 289.76, 1999: 363.20, 2000: 691.84, 2001: 610.71, 2002: 339.68,
    2003: 203.00, 2004: 232.93, 2005: 203.54, 2006: 322.93, 2007: 357.34, 2008: 355.12,
    2009: 265.65, 2010: 530.61, 2011: 738.51, 2012: 649.27, 2013: 729.58, 2014: 809.89,
    2015: 694.99, 2016: 617.39, 2017: 874.30, 2018: 1036.43, 2019: 1544.31, 2020: 2205.27,
    2021: 2419.18, 2022: 2133.81, 2023: 1351.66, 2024: 994.90, 2025: 1100.0,
}


def read_pink_sheet(path):
    ws = openpyxl.load_workbook(path, read_only=True, data_only=True)["Monthly Prices"]
    rows = list(ws.iter_rows(values_only=True))
    header = next(r for r in rows if r and "Gold" in r)
    col = {name: header.index(name) for name in ("Gold", "Silver", "Platinum")}
    months = []
    for r in rows:
        key = str(r[0] or "")
        if len(key) == 7 and key[4] == "M" and int(key[:4]) >= FIRST_YEAR:
            vals = [r[col[n]] for n in ("Gold", "Silver", "Platinum")]
            if all(isinstance(v, (int, float)) and v > 0 for v in vals):
                months.append((int(key[:4]), int(key[5:]), *map(float, vals)))
    return months


def interp_yearly(yearly, t):
    """Log-linear between mid-year points; t in fractional years."""
    years = sorted(yearly)
    pts = [(y + 0.5, math.log(yearly[y])) for y in years]
    if t <= pts[0][0]:
        return pts[0][1]
    if t >= pts[-1][0]:
        return pts[-1][1]
    for (t0, v0), (t1, v1) in zip(pts, pts[1:]):
        if t0 <= t <= t1:
            return v0 + (v1 - v0) * (t - t0) / (t1 - t0)


def palladium(months):
    t_of = lambda y, m: y + (m - 0.5) / 12.0
    # platinum's yearly average from the Pink Sheet, to find its monthly deviations
    pt_year = {}
    for y, m, _, _, pt in months:
        pt_year.setdefault(y, []).append(math.log(pt))
    pt_yearly = {y: math.exp(sum(v) / len(v)) for y, v in pt_year.items() if len(v) == 12}
    first, last = min(PALLADIUM_YEARLY), max(PALLADIUM_YEARLY)
    out = []
    for y, m, _, _, pt in months:
        t = t_of(y, m)
        clamp = min(max(t, first + 0.5), last + 0.5)
        ratio = interp_yearly(PALLADIUM_YEARLY, clamp) - interp_yearly(pt_yearly, clamp)
        if first + 0.5 <= t <= last + 0.5:
            out.append(math.exp(interp_yearly(PALLADIUM_YEARLY, t) + math.log(pt) - interp_yearly(pt_yearly, t)))
        else:
            out.append(math.exp(math.log(pt) + ratio))
    return out


def main():
    months = read_pink_sheet(sys.argv[1])
    pd = palladium(months)
    y0, m0 = months[0][0], months[0][1]
    lines = [
        "class_name PriceHistory",
        "## Monthly average metal prices, USD per troy ounce, from %d-%02d to %d-%02d." % (y0, m0, months[-1][0], months[-1][1]),
        "## Made by tools/prices/build_history.py; do not edit by hand.",
        "## Gold, silver, platinum: World Bank Commodity Price Data (The Pink Sheet), CC BY 4.0.",
        "## Palladium: U.S. Geological Survey yearly averages (public domain), shaped by platinum.",
        "",
        "const FIRST_YEAR := %d" % y0,
        "const FIRST_MONTH := %d" % m0,
        "const CREDIT := \"Historical prices: World Bank Commodity Price Data (The Pink Sheet), CC BY 4.0; U.S. Geological Survey.\"",
        "## One row per month: XAU, XAG, XPT, XPD.",
        "const MONTHS := [",
    ]
    for (y, m, au, ag, pt), p in zip(months, pd):
        lines.append("\t[%g, %g, %g, %g], # %d-%02d" % (round(au, 2), round(ag, 3), round(pt, 2), round(p, 2), y, m))
    lines.append("]")
    with open(OUT, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote %d months to %s" % (len(months), OUT))


if __name__ == "__main__":
    main()
