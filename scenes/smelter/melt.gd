class_name Melt
extends RefCounted
## One melt at the Smelter: the scrap lots of one metal go into the crucible and come out
## as a cast bar. The physics are simple but every step can cost metal:
##   sort   steel bits don't melt; each one left in adds dross and spoils the bar
##   heat   the gas valve drives the furnace toward a temperature with some lag; the charge
##          melts above its melting point, and too much heat fumes metal away
##   flux   borax clears the dross off the melt; too little leaves inclusions in the bar,
##          too much makes a glassy slag that traps beads of metal
##   pour   tilting the crucible pours it into the ingot mould; out of the furnace it
##          cools fast, so pour hot, steady and not too fast. Metal that freezes in the
##          crucible goes back to the scrap bin; a pause mid-pour leaves a cold shut.
## The result is assayed and the bullion dealer pays for the fine metal in the bar.

const AMBIENT := 20.0
const MAX_TEMP := 1450.0
## Seconds for the furnace to close most of the gap to where the gas valve drives it.
const HEAT_TAU := 3.0
## Degrees a second the crucible loses once it's out of the furnace.
const COOL_RATE := 22.0
## Pour band above the melting point, and where fuming starts.
const BAND := Vector2(60.0, 150.0)
const FUME_FROM := 200.0
## Share of the fine metal fumed away per second per 100 degrees over FUME_FROM.
const FUME_RATE := 0.006
## Seconds to melt the whole charge at 80 degrees over its melting point.
const MELT_SECONDS := 3.0
## One pinch of borax clears this much dross (0-1), or adds as much slag when there's none.
const FLUX_STEP := 0.2
const STEEL_DROSS := 0.12
## Share of the fine metal lost to each unit of dross left at the pour, and of slag.
const DROSS_LOSS := 0.05
const SLAG_LOSS := 0.04
## What always stays behind in the crucible wall and the dust.
const BASE_LOSS := 0.003
## Holding the pour tilts the crucible up at TILT_UP a second; let go and it eases back at
## TILT_DOWN. It starts to pour past LIP of its tilt; at full tilt it pours FLOW_MAX of
## the charge a second, and above SPLASH_FLOW it splashes SPLASH_LOSS of the excess.
const TILT_UP := 0.8
const TILT_DOWN := 0.4
const LIP := 0.3
const FLOW_MAX := 0.65
const SPLASH_FLOW := 0.42
const SPLASH_LOSS := 0.3
## A pause longer than this mid-pour leaves a cold shut when the pour starts again.
const COLD_SHUT_GAP := 0.6
## What the dealer takes off for a flawed bar, as a share of its value.
const PENALTY := {"cold_shut": 0.01, "steel": 0.03, "inclusions": 0.015}

var metal := "XAU"
var lots: Array[Dictionary] = []
var grams := 0.0 # precious alloy in the charge
var fine := 0.0 # fine metal in it (the truth, which the assay reveals)
var claimed_fine := 0.0 # what the lots' stamps promise
var cost := 0.0
var steel := 0 # steel bits still in the charge
var steel_g := 0.0
var steel_pulled := 0
var dirt := 0.0
var melting_point := 1000.0

var temp := AMBIENT
var gas := 0.0
var molten := 0.0
var dross := 0.0
var slag := 0.0
var flux_pinches := 0
var fumed := 0.0 # fine grams
var splashed := 0.0 # fine grams
var tilt := 0.0
var lifted := false
var poured := 0.0 # share of the charge in the mould
var cold_shut := false
var frozen := false
var done := false
var elapsed := 0.0
var _gap := 0.0
var _draught := 0.0
var _flowing := false
var _rng := RandomNumberGenerator.new()


## A melt of every lot in `lots` (all one metal).
static func of(batch: Array[Dictionary], seed := 0) -> Melt:
	var m := Melt.new()
	m._rng.seed = seed if seed != 0 else randi()
	m.lots = batch
	if not batch.is_empty():
		m.metal = batch[0].metal
	var dirt_g := 0.0
	for lot in batch:
		m.grams += float(lot.grams)
		m.fine += float(lot.grams) * float(lot.purity)
		m.claimed_fine += ScrapYard.gross(lot) * float(lot.claimed)
		m.cost += float(lot.cost)
		m.steel += int(lot.steel)
		m.steel_g += int(lot.steel) * float(lot.steel_g)
		dirt_g += float(lot.dirt) * float(lot.grams)
	m.dirt = dirt_g / maxf(m.grams, 0.001)
	m.melting_point = melting_point_of(m.metal, m.purity())
	m.dross = m.dirt
	return m


## Where an alloy of `purity` melts: gold alloys melt lower the more copper and silver
## they carry, and sterling a little below fine silver.
static func melting_point_of(metal_sym: String, purity_share: float) -> float:
	if metal_sym == "XAG":
		return lerpf(880.0, 961.0, clampf((purity_share - 0.8) / 0.2, 0.0, 1.0))
	return lerpf(870.0, 1064.0, clampf((purity_share - 0.4) / 0.6, 0.0, 1.0))


func purity() -> float:
	return fine / maxf(grams, 0.001)


func band() -> Vector2:
	return Vector2(melting_point + BAND.x, melting_point + BAND.y)


func in_band() -> bool:
	var b := band()
	return temp >= b.x and temp <= b.y


## Pulls one steel bit out of the scrap with the magnet, before the melt.
func pull_steel() -> bool:
	if steel <= 0 or molten > 0.0:
		return false
	steel -= 1
	steel_pulled += 1
	return true


## The lots as they stand before anything melted, less the steel the magnet took out,
## for when you walk away from the furnace before the pour.
func unmelted_lots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pulled := steel_pulled
	for lot in lots:
		var copy := lot.duplicate()
		var n := mini(pulled, int(copy.steel))
		copy.steel = int(copy.steel) - n
		pulled -= n
		out.append(copy)
	return out


## The charge goes into the crucible: steel left in it adds to the dross.
func load_crucible() -> void:
	dross = clampf(dirt + steel * STEEL_DROSS, 0.0, 1.0)


func set_gas(v: float) -> void:
	gas = clampf(v, 0.0, 1.0)


## A pinch of borax: clears dross, or makes slag when the melt is already clean.
func add_flux() -> void:
	if done or lifted:
		return
	flux_pinches += 1
	if dross > 0.001:
		var cleared := minf(dross, FLUX_STEP)
		dross -= cleared
		slag += (FLUX_STEP - cleared) * 0.5
	else:
		slag += FLUX_STEP


## Where the furnace is heading with the gas valve as it is.
func target_temp() -> float:
	return AMBIENT + gas * (MAX_TEMP - AMBIENT)


## Runs the melt for `delta` seconds; `pouring` is whether the pour is held.
func advance(delta: float, pouring: bool) -> void:
	if done:
		return
	elapsed += delta
	if pouring and molten > 0.0:
		lifted = true
	if lifted:
		tilt = clampf(tilt + (TILT_UP if pouring else -TILT_DOWN) * delta, 0.0, 1.0)
		temp = maxf(AMBIENT, temp - COOL_RATE * delta)
	else:
		# draughts from the vent nudge the furnace about
		_draught = lerpf(_draught, _rng.randf_range(-1.0, 1.0), minf(delta * 0.8, 1.0))
		var target := target_temp() + _draught * 12.0 * gas
		temp += (target - temp) * (1.0 - exp(-delta / HEAT_TAU))
	var over := temp - melting_point
	if over > 0.0 and molten < 1.0:
		molten = minf(1.0, molten + clampf(over / 80.0, 0.0, 1.5) * delta / MELT_SECONDS)
	if over > FUME_FROM and molten > 0.0:
		var rate := FUME_RATE * (over - FUME_FROM) / 100.0 * (1.5 if metal == "XAG" else 1.0)
		fumed += fine * rate * molten * delta
	if lifted:
		_pour(delta)


func _pour(delta: float) -> void:
	if temp < melting_point and molten > 0.0:
		frozen = poured < molten - 0.002
		_finish()
		return
	var flow := maxf(0.0, tilt - LIP) / (1.0 - LIP) * FLOW_MAX
	var left := molten - poured
	var step := minf(flow * delta, left)
	if step > 0.0:
		if not _flowing and _gap > COLD_SHUT_GAP and poured > 0.03:
			cold_shut = true
		_flowing = true
		_gap = 0.0
		poured += step
		if flow > SPLASH_FLOW:
			splashed += fine * (flow - SPLASH_FLOW) / FLOW_MAX * SPLASH_LOSS * step
	else:
		if _flowing:
			_flowing = false
		if poured > 0.0:
			_gap += delta
	if molten >= 1.0 and molten - poured <= 0.002:
		poured = molten
		_finish()


## Ends the pour where it stands: whatever is left in the crucible freezes there.
func stop() -> void:
	if not done:
		frozen = poured < molten - 0.002 or molten < 1.0
		_finish()


func _finish() -> void:
	done = true
	tilt = 0.0


func flow_rate() -> float:
	if not lifted or done:
		return 0.0
	return maxf(0.0, tilt - LIP) / (1.0 - LIP) * FLOW_MAX


## Fine metal left after the fumes, the dross and slag losses and the crucible's share.
func _fine_kept() -> float:
	var lost := fumed + fine * (BASE_LOSS + dross * DROSS_LOSS + minf(slag, 1.0) * SLAG_LOSS)
	return maxf(0.0, fine - lost)


## The assay of the finished bar and what the dealer pays:
## {"grams", "fine", "purity", "recovery", "payout", "cost", "flaws", "skull"}.
## `skull` is the lot that goes back to the bin: unpoured metal and unmelted scrap.
func result() -> Dictionary:
	var kept := _fine_kept()
	var bar_fine := maxf(0.0, kept * poured - splashed)
	var p := purity()
	var bar_steel := steel_g if poured > 0.0 else 0.0
	var bar_grams := bar_fine / maxf(p, 0.001) + bar_steel
	var flaws: Array[String] = []
	if cold_shut:
		flaws.append("cold_shut")
	if steel > 0 and poured > 0.0:
		flaws.append("steel")
	if dross > 0.3 and poured > 0.0:
		flaws.append("inclusions")
	var penalty := 0.0
	for f in flaws:
		penalty += PENALTY[f]
	var payout := bar_fine * ScrapYard.spot_per_gram(metal) * ScrapYard.cast_share() * (1.0 - penalty)
	var share := clampf(poured, 0.0, 1.0)
	var skull := {}
	if share < 0.999:
		var back_fine := kept * (1.0 - share)
		var first: Dictionary = lots[0] if not lots.is_empty() else {}
		skull = {"name": "Metal left in the crucible", "metal": metal, "stamp": "%.0f" % (p * 1000.0), "claimed": p,
			"purity": snappedf(p, 0.0001), "grams": snappedf(back_fine / maxf(p, 0.001), 0.01), "steel": 0 if poured > 0.0 else steel,
			"steel_g": float(first.get("steel_g", 0.0)), "dirt": snappedf(dross, 0.01), "art": "skull",
			"cost": snappedf(cost * (1.0 - share), 0.01), "seed": int(first.get("seed", 1))}
	return {"grams": bar_grams, "fine": bar_fine, "purity": bar_fine / maxf(bar_grams, 0.001),
		"recovery": bar_fine / maxf(fine * share, 0.001) if share > 0.0 else 0.0,
		"payout": payout, "cost": cost * share, "flaws": flaws, "skull": skull}
