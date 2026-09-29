extends SpecialCareer
## Music: compose songs (quality from the Music skill, CHA and musical talent),
## record albums, tour, sign with a label. Fans generate yearly streaming
## income; a legendary hit can make you a star overnight.


func start_state(_p: Dictionary) -> Dictionary:
	return {"fans": 50.0, "songs": [], "albums": 0, "best_album": 0.0, "label": false, "hits": 0}


func _song_quality(p: Dictionary) -> float:
	var q: float = 10.0 + sim.skills.level(p, "music") * 5.0 + sim.skills.level(p, "soul_melody") * 9.0
	q += stat(p, "cha") * 0.6 + stat(p, "dex") * 0.3 + (float(p.hidden.talent_music) - 50.0) * 0.4
	return clampf(q * sim.rng.randf_range(0.7, 1.3) * (1.0 + sim.gamer.mod("charm")), 1.0, 999.0)


func actions(_p: Dictionary, st: Dictionary) -> Array:
	var out := [act("compose")]
	out.append(act("record", 1, 0.0 if st.label else 3000.0, "" if st.songs.size() >= 5 else "sc.music.need_songs"))
	out.append(act("tour", 2, 1500.0, "" if float(st.fans) >= 1000.0 else "sc.need_fans"))
	out.append(act("label", 0, 0.0, "" if not st.label and float(st.fans) >= 5000.0 else ("sc.music.has_label" if st.label else "sc.need_fans")))
	return out


func perform(p: Dictionary, st: Dictionary, action: String, ctx: Dictionary) -> Dictionary:
	match action:
		"compose":
			var q: float = _song_quality(p)
			st.songs.append(q)
			sim.skills.add_xp(p, "music", 10.0)
			sim.skills.add_xp(p, "soul_melody", 10.0)
			counter("act.practice_music")
			give_exp(p, 15.0 + q * 0.2, ctx)
			if q >= 120.0 and sim.prob.roll_neutral(0.25):
				st.fans = grow_audience(float(st.fans), float(st.fans) * 0.5 + 5000.0)
				st.hits = int(st.hits) + 1
				fame(p, 8.0)
				log_major("log.music_hit")
				return res("sc.music.compose_hit", {"q": int(q)})
			return res("sc.music.compose", {"q": int(q)})
		"record":
			var avg: float = 0.0
			for q in st.songs:
				avg += float(q)
			avg /= maxf(1.0, st.songs.size())
			st.songs = []
			st.albums = int(st.albums) + 1
			var sales: float = (float(st.fans) * 0.6 + avg * 40.0) * sim.rng.randf_range(0.5, 1.6) * (1.6 if st.label else 1.0)
			var income := sales * (4.0 if st.label else 2.5)
			give_money(p, income, ctx)
			st.fans = grow_audience(float(st.fans), sales * 0.25)
			st.best_album = maxf(float(st.best_album), sales)
			fame(p, clampf(sales / 20000.0, 0.5, 12.0))
			give_exp(p, 60.0 + avg, ctx)
			counter("music.albums")
			if sales >= 1000000.0:
				counter("music.platinum")
				log_major("log.music_platinum", {"n": int(st.albums)})
			return res("sc.music.recorded", {"sales": int(sales)})
		"tour":
			var income: float = float(st.fans) * sim.rng.randf_range(0.6, 1.2)
			give_money(p, income, ctx)
			st.fans = grow_audience(float(st.fans), float(st.fans) * 0.25)
			p.attrs.stress = clampf(float(p.attrs.stress) + 15.0, 0, 100)
			fame(p, 3.0)
			give_exp(p, 80.0, ctx)
			if sim.prob.roll_neutral(0.25):
				sim.events.queue_event("travel_romance")
			return res("sc.music.toured", {"v": int(income)})
		"label":
			if chance({"base": 0.3, "mods": [{"path": "player.fame", "per": 0.01}, {"path": "stat.cha", "per": 0.004, "offset": 10.0, "max": 0.3}]}):
				st.label = true
				give_money(p, float(st.fans) * 2.0, ctx)
				log_major("log.music_label")
				return res("sc.music.label_ok")
			return res("sc.music.label_no", {}, false)
	return {"ok": false, "reason": "ui.invalid"}


func tick(p: Dictionary, st: Dictionary) -> void:
	var streams: float = float(st.fans) * 0.35 * (1.5 if st.label else 1.0)
	sim.finance.add_cash(p, streams)
	st.last_income = streams
	st.fans = maxf(10.0, float(st.fans) * 0.93)
	if float(st.fans) > 1000000.0:
		counter("music.million_fans")


func summary(_p: Dictionary, st: Dictionary) -> Array:
	return [["sc.fans", Fmt.num(st.fans)], ["sc.music.songs", str(st.songs.size())], ["sc.music.albums", str(st.albums)],
		["sc.music.label_word", "✔" if st.label else "—"], ["sc.last_income", Fmt.money(float(st.get("last_income", 0)))]]
