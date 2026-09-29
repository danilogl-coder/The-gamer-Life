class_name Persona
extends RefCounted
## Personality model shared by every character (player and NPCs).
##
##  big5        o/c/e/a/n 0..100 (openness, conscientiousness, extraversion,
##              agreeableness, neuroticism) from traits + hidden values
##  voice       how the person talks (sweet, formal, slang, blunt, sarcastic,
##              shy, dramatic, nerdy, calm, kid, elder). Recomputed as people
##              age: a slangy teen can become a formal 60 year old.
##  interests   2-3 conversation topics
##  politics    -100 (progressive) .. +100 (conservative)
##  aspiration  what the person wants out of life (drives NPC life events)
##  quirk       a small personal habit that shows up in scenes
##  catch       index of the personal catchphrase for the voice
##
## Nothing here is scripted: the dialogue engine and NPC life simulation read
## these numbers as facts, so two mothers with different personas never talk
## or live the same way.

const BIG5 := ["o", "c", "e", "a", "n"]
const VOICES := ["sweet", "formal", "slang", "blunt", "sarcastic", "shy", "dramatic", "nerdy", "calm"]
const INTERESTS := ["music", "sports", "games", "cooking", "politics", "faith", "fashion", "tech",
	"books", "gardening", "cars", "travel", "money", "gossip", "movies", "animals", "fitness",
	"dungeons", "art", "science", "nature", "history"]
const ASPIRATIONS := ["family", "wealth", "career", "fame", "knowledge", "adventure", "peace", "power", "faith", "romance"]
const QUIRKS := ["late", "hums", "coffee", "plants", "puns", "collector", "early_bird", "night_owl",
	"clean_freak", "messy", "superstitious", "horoscope", "gym_talk", "old_songs", "phone_addict",
	"cooks_too_much", "nail_biter", "storyteller", "penny_pincher", "overdresser"]
const CATCHPHRASES := 4


## Creates the persona for a freshly generated character.
static func build(ch: Dictionary, sim) -> void:
	var h: Dictionary = ch.get("hidden", {})
	var b := {}
	for k in BIG5:
		b[k] = sim.rng.randn(50, 12)
	b.a += (float(h.get("empathy", 50)) - 50) * 0.35 + (float(h.get("generosity", 50)) - 50) * 0.25 - (float(h.get("aggression", 50)) - 50) * 0.3
	b.c += (float(h.get("professionalism", 50)) - 50) * 0.35 - (float(h.get("impulsivity", 50)) - 50) * 0.3 + (float(h.get("willpower", 50)) - 50) * 0.2
	b.n += -(float(h.get("stress_tolerance", 50)) - 50) * 0.4 + (float(h.get("craziness", 50)) - 50) * 0.2
	b.o += (float(h.get("craziness", 50)) - 50) * 0.15 + (float(h.get("courage", 50)) - 50) * 0.15 - (float(h.get("religiousness", 50)) - 50) * 0.1
	b.e += (float(h.get("courage", 50)) - 50) * 0.15 + (float(h.get("ambition", 50)) - 50) * 0.1
	for t in ch.get("traits", []):
		var off: Dictionary = sim.data.get_def("traits", t).get("big5", {})
		for k in off:
			b[k] = float(b[k]) + float(off[k])
	for k in BIG5:
		b[k] = clampf(float(b[k]), 1, 99)
	ch.persona = {
		"big5": b,
		"interests": _pick_interests(ch, b, sim),
		"politics": clampf(sim.rng.randn(0, 35) + (float(h.get("religiousness", 50)) - 50) * 0.6 - (float(b.o) - 50) * 0.6
			+ (["upper", "elite"].count(ch.get("wealth", "")) * 15.0) + (int(ch.get("age", 20)) - 40) * 0.3, -100, 100),
		"aspiration": _pick_aspiration(h, b, sim),
		"quirk": sim.rng.pick(QUIRKS),
		"catch": sim.rng.randi_range(0, CATCHPHRASES - 1),
		"voice_noise": sim.rng.randf_range(-8, 8),
	}
	refresh_voice(ch)


## Children blend both parents' personalities with noise (nature + nurture).
static func inherit(child: Dictionary, parents: Array, sim) -> void:
	if not child.has("persona"):
		build(child, sim)
	var have: Array = parents.filter(func(x): return not x.is_empty() and x.has("persona"))
	if have.is_empty():
		return
	for k in BIG5:
		var avg := 0.0
		for par in have:
			avg += float(par.persona.big5[k])
		avg /= have.size()
		child.persona.big5[k] = clampf(float(child.persona.big5[k]) * 0.6 + avg * 0.4, 1, 99)
	var pol := 0.0
	for par in have:
		pol += float(par.persona.politics)
	child.persona.politics = clampf(float(child.persona.politics) * 0.5 + pol / have.size() * 0.5, -100, 100)
	if sim.rng.randf() < 0.35:
		var par: Dictionary = sim.rng.pick(have)
		var shared: String = sim.rng.pick(par.persona.interests)
		if not child.persona.interests.has(shared):
			child.persona.interests[0] = shared
	refresh_voice(child)


static func ensure(ch: Dictionary, sim) -> void:
	if not ch.has("persona"):
		build(ch, sim)


## Voice depends on age and personality, so it evolves over a lifetime.
static func refresh_voice(ch: Dictionary) -> void:
	var pz: Dictionary = ch.persona
	var b: Dictionary = pz.big5
	var age := int(ch.get("age", 20))
	if age < 12:
		pz.voice = "kid"
		return
	var edu: float = float(ch.get("education", {}).get("completed", []).size()) * 6.0
	var scores := {
		"sweet": float(b.a) + float(b.e) * 0.4,
		"formal": float(b.c) + maxf(0, age - 35) * 0.8 + edu,
		"slang": float(b.e) + maxf(0, 28 - age) * 3.0 - edu * 0.5,
		"blunt": (100.0 - float(b.a)) + float(b.c) * 0.3,
		"sarcastic": float(b.o) * 0.6 + (100.0 - float(b.a)) * 0.8,
		"shy": (100.0 - float(b.e)) * 1.2,
		"dramatic": float(b.n) + float(b.e) * 0.4,
		"nerdy": float(b.o) * 0.7 + float(ch.get("hidden", {}).get("academic", 50)) * 0.6,
		"calm": (100.0 - float(b.n)) + float(b.a) * 0.3,
	}
	scores[VOICES[int(absf(float(pz.get("voice_noise", 0)) * 7)) % VOICES.size()]] += float(pz.get("voice_noise", 0))
	var best := "calm"
	for v in VOICES:
		if float(scores[v]) > float(scores[best]):
			best = v
	if age >= 70 and best in ["slang", "shy"]:
		best = "elder"
	pz.voice = best


static func _pick_interests(ch: Dictionary, b: Dictionary, sim) -> Array:
	var h: Dictionary = ch.get("hidden", {})
	var age := int(ch.get("age", 20))
	var w := {}
	for i in INTERESTS:
		w[i] = 1.0
	w.music += float(h.get("talent_music", 50)) / 25.0
	w.sports += float(h.get("talent_sport", 50)) / 25.0 + float(h.get("athleticism", 50)) / 40.0
	w.fitness += float(h.get("athleticism", 50)) / 30.0
	w.art += float(h.get("talent_art", 50)) / 25.0
	w.fashion += float(h.get("talent_art", 50)) / 50.0 + (2.0 if ch.get("traits", []).has("materialistic") else 0.0)
	w.books += float(h.get("academic", 50)) / 30.0
	w.science += float(h.get("academic", 50)) / 35.0 + float(b.o) / 60.0
	w.faith += maxf(0, float(h.get("religiousness", 50)) - 45) / 8.0
	w.money += float(h.get("greed", 50)) / 30.0
	w.cars += float(h.get("greed", 50)) / 60.0
	w.travel += float(b.o) / 30.0
	w.gossip += float(b.e) / 40.0 + maxf(0, 50 - float(b.a)) / 40.0
	w.politics += absf(float(h.get("religiousness", 50)) - 50) / 30.0 + maxf(0, age - 40) / 20.0
	w.games += maxf(0, 30 - age) / 6.0
	w.gardening += maxf(0, age - 45) / 10.0
	w.history += maxf(0, age - 50) / 15.0 + float(h.get("academic", 50)) / 80.0
	w.dungeons += 3.0 if ch.get("gamer", {}).get("awakened", false) else 0.0
	w.cooking += float(b.a) / 60.0
	w.nature += float(b.o) / 60.0 + maxf(0, age - 50) / 25.0
	var keys: Array = INTERESTS.duplicate()
	var out: Array = []
	var n: int = sim.rng.randi_range(2, 3)
	while out.size() < n:
		var ws: Array = []
		for k in keys:
			ws.append(float(w[k]))
		var pick = sim.rng.pick_weighted(keys, ws)
		out.append(pick)
		keys.erase(pick)
	return out


static func _pick_aspiration(h: Dictionary, b: Dictionary, sim) -> String:
	var w := [
		float(h.get("empathy", 50)) + float(b.a) * 0.5,          # family
		float(h.get("greed", 50)) * 1.2,                          # wealth
		float(h.get("ambition", 50)) + float(b.c) * 0.5,          # career
		float(b.e) * 0.8 + float(h.get("ambition", 50)) * 0.4,    # fame
		float(h.get("academic", 50)) + float(b.o) * 0.4,          # knowledge
		float(b.o) + float(h.get("courage", 50)) * 0.4,           # adventure
		(100.0 - float(b.n)) * 0.9,                               # peace
		float(h.get("aggression", 50)) * 0.6 + float(h.get("ambition", 50)) * 0.5,  # power
		maxf(0, float(h.get("religiousness", 50)) - 40) * 2.0,    # faith
		float(b.e) * 0.4 + float(b.a) * 0.4 + 10.0,               # romance
	]
	var sharp: Array = []
	for x in w:
		sharp.append(pow(maxf(1.0, x) / 50.0, 3.0))
	return sim.rng.pick_weighted(ASPIRATIONS, sharp)


# ---------------------------------------------------------------------------
# Derived helpers used by dialogue / NPC life
# ---------------------------------------------------------------------------

static func trait_of(ch: Dictionary, k: String) -> float:
	return float(ch.get("persona", {}).get("big5", {}).get(k, 50.0))


static func mood(ch: Dictionary) -> float:
	return float(ch.get("attrs", {}).get("happiness", 60.0))


static func mood_band(ch: Dictionary) -> String:
	var m := mood(ch)
	if m < 25:
		return "miserable"
	if m < 45:
		return "down"
	if m < 70:
		return "ok"
	return "happy"


static func age_band(age: int) -> String:
	if age < 6:
		return "toddler"
	if age < 12:
		return "child"
	if age < 18:
		return "teen"
	if age < 30:
		return "young"
	if age < 50:
		return "adult"
	if age < 70:
		return "mature"
	return "elder"


static func politics_label(v: float) -> String:
	if v < -35:
		return "progressive"
	if v > 35:
		return "conservative"
	return "moderate"
