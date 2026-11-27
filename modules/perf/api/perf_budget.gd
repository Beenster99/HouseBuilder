class_name PerfBudget
extends RefCounted
## The performance targets in one place: 60 fps on the host with up to 3 players, and the
## share of each frame (and of the network) the game's systems may use. The tests in
## modules/perf/tests and the benchmark (godot --path . -- --bench) judge against these.

const TARGET_FPS := 60
const FRAME_MS := 1000.0 / 60.0
## A frame counts as over budget past FRAME_MS * SLACK (vsync jitter is not a miss).
const SLACK := 1.1
## A single frame this long is a hitch: players see it as a stutter.
const HITCH_MS := 50.0

## What a recorded window must meet (FrameStats.meets()).
const TARGET := {
	"frame_ms": FRAME_MS,
	"p95_ms": 20.0,
	"max_over_budget": 0.05,
	"max_hitches": 2,
}

## CPU time per frame the game's own scripts and physics may take, so the renderer keeps
## the rest (measured headless, where there is no rendering).
const SCRIPT_FRAME_MS := 8.0
## One-off work the player waits for in a click (an edit, a stress test, a route): above
## this it shows as a hitch, so it must be spread over frames or run on a thread.
const CLICK_MS := 50.0
## A button the player presses and waits on (stress test, M&E route): above this the host
## freezes for everyone, so it must run on a thread or in slices.
const HEAVY_MS := 500.0
## Opening a scene with the biggest building (behind the loading screen).
const OPEN_MS := 3000.0

## Jolt bodies: chunks standing in a demolition scene, and awake (falling) at once.
const MAX_BODIES := 6000
const MAX_AWAKE := 1500

## Network: the host's upload to each peer, bytes per second, for mover streams. Home
## upload links are often 10 Mbit/s or less; two peers must fit with room to spare.
const MOVER_BYTES_PER_PEER := 256 * 1024
## The interpolation delay every peer renders movers at, s (all players see things at the
## same moment, this far behind the host).
const MAX_VIEW_DELAY := 0.15
## A building edit must reach every peer within this, s, on a LAN.
const MAX_EVENT_LAG := 0.25
