class_name StatisticsStore
extends RefCounted

const KEEP_DAYS := 30

static func sanitize(raw: Variant) -> Dictionary:
	var data: Dictionary = raw.duplicate(true) if raw is Dictionary else {}
	var days: Dictionary = data.get("days", {}) if data.get("days", {}) is Dictionary else {}
	var keys := days.keys()
	keys.sort()
	while keys.size() > KEEP_DAYS:
		days.erase(keys.pop_front())
	return {"days": days, "top5_entries": maxi(0, int(data.get("top5_entries", 0)))}

static func record(raw: Dictionary, score: int, band: GameDef.Faixa, entered_top5: bool) -> Dictionary:
	var data := sanitize(raw)
	var days: Dictionary = data["days"]
	var now := Time.get_datetime_dict_from_system()
	var key := "%04d-%02d-%02d" % [now.year, now.month, now.day]
	var day: Dictionary = days.get(key, {
		"plays": 0, "score_sum": 0, "best": 0,
		"weak": 0, "medium": 0, "strong": 0, "hours": {},
	})
	day["plays"] = int(day.get("plays", 0)) + 1
	day["score_sum"] = int(day.get("score_sum", 0)) + score
	day["best"] = maxi(int(day.get("best", 0)), score)
	match band:
		GameDef.Faixa.FORTE:
			day["strong"] = int(day.get("strong", 0)) + 1
		GameDef.Faixa.MEDIA:
			day["medium"] = int(day.get("medium", 0)) + 1
		_:
			day["weak"] = int(day.get("weak", 0)) + 1
	var hours: Dictionary = day.get("hours", {})
	var hour := "%02d" % now.hour
	hours[hour] = int(hours.get(hour, 0)) + 1
	day["hours"] = hours
	days[key] = day
	data["days"] = days
	if entered_top5:
		data["top5_entries"] = int(data.get("top5_entries", 0)) + 1
	return sanitize(data)

static func summary(raw: Dictionary) -> Dictionary:
	var data := sanitize(raw)
	var days: Dictionary = data["days"]
	var total := 0
	var sum := 0
	var best := 0
	var weak := 0
	var medium := 0
	var strong := 0
	var last7 := 0
	var ordered_keys := days.keys()
	ordered_keys.sort()
	var recent_start := maxi(0, ordered_keys.size() - 7)
	for i in range(recent_start, ordered_keys.size()):
		last7 += int((days[ordered_keys[i]] as Dictionary).get("plays", 0))
	for day in days.values():
		total += int(day.get("plays", 0))
		sum += int(day.get("score_sum", 0))
		best = maxi(best, int(day.get("best", 0)))
		weak += int(day.get("weak", 0))
		medium += int(day.get("medium", 0))
		strong += int(day.get("strong", 0))
	var today_key := Time.get_date_string_from_system()
	var today: Dictionary = days.get(today_key, {})
	return {
		"today": int(today.get("plays", 0)),
		"last7": last7,
		"total": total,
		"average": int(round(float(sum) / maxf(float(total), 1.0))),
		"best": best,
		"weak": weak,
		"medium": medium,
		"strong": strong,
		"weak_percent": 100.0 * float(weak) / maxf(float(total), 1.0),
		"medium_percent": 100.0 * float(medium) / maxf(float(total), 1.0),
		"strong_percent": 100.0 * float(strong) / maxf(float(total), 1.0),
		"top5_entries": int(data.get("top5_entries", 0)),
	}
