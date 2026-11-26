class_name ContractPayout
extends RefCounted
## Settles a finished contract: what the client pays, what the build cost, the profit, and
## the change in reputation, with a line of explanation for each.
##
##   var s := ContractPayout.settle(brief, assessment, {"days": schedule.days})
##   # {brief_id, passed, fee, bonus, cost, late_days, late_penalty, profit, reputation, lines}
##
## Rules: the fee is paid only if every hard requirement passes; each goal met adds its
## bonus. Finishing late costs LATE_SHARE of the fee a day, up to MAX_LATE_SHARE. The build
## cost is always spent. Reputation: the brief's reward for a pass, less one a week late (at
## least 1); a fail loses half the reward.

const LATE_SHARE := 0.005
const MAX_LATE_SHARE := 0.5


## build: {days: the construction schedule's length}. Omit days for an on-time handover.
static func settle(brief: Dictionary, assessment: Dictionary, build: Dictionary = {}) -> Dictionary:
	var b := ContractBrief.normalize(brief)
	var passed := bool(assessment.get("ok", false))
	var cost := float(assessment.get("cost", 0.0))
	var deadline := int(b.get("deadline_days", 0))
	var days := int(ceil(float(build.get("days", deadline))))
	var late := maxi(0, days - deadline) if deadline > 0 else 0
	var fee := float(b.fee) if passed else 0.0
	var bonus := float(assessment.get("bonus", 0.0)) if passed else 0.0
	var penalty := minf(fee * LATE_SHARE * late, fee * MAX_LATE_SHARE)
	var reward := int((b.reputation as Dictionary).get("reward", 1))
	var rep := maxi(1, reward - late / 7) if passed else -ceili(reward / 2.0)
	var profit := fee + bonus - penalty - cost
	var lines := PackedStringArray()
	if passed:
		lines.append("%s paid the fee of %s." % [_client(b), ContractValidator.money(fee)])
		if bonus > 0.0:
			lines.append("Bonus goals met: %s." % ContractValidator.money(bonus))
	else:
		var failed := PackedStringArray()
		for it: Dictionary in assessment.get("items", []):
			if it.hard and not it.ok:
				failed.append(str(it.label).to_lower())
		lines.append("Not paid: the building did not meet %s." % ", ".join(failed))
	lines.append("The build cost %s." % ContractValidator.money(cost))
	if late > 0:
		lines.append("Handed over %d day%s late: %s off the fee." % [late, "" if late == 1 else "s", ContractValidator.money(penalty)])
	elif deadline > 0:
		lines.append("Handed over on time (%d of %d days)." % [days, deadline])
	lines.append("%s of %s." % ["Profit" if profit >= 0.0 else "A loss", ContractValidator.money(absf(profit))])
	lines.append("Reputation %s%d." % ["+" if rep >= 0 else "", rep])
	return {"brief_id": str(b.id), "title": str(b.title), "passed": passed, "fee": fee, "bonus": bonus, "cost": cost,
			"days": days, "late_days": late, "late_penalty": penalty, "profit": profit, "reputation": rep, "lines": lines}


static func _client(b: Dictionary) -> String:
	var c := str(b.get("client", ""))
	return c if c != "" else "The client"
