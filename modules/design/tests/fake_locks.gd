extends Node
## Stands in for the contracts bus in tests: answers locked_tier from a table.

var locks: Dictionary = {}


func locked_tier(unlock_id: String) -> int:
	return int(locks.get(unlock_id, 0))
