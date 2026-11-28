# faces: talking cartoon faces

Plan: "Talking avatar faces plan" (https://claude.ai/artifact/2MdSco4an3sYKxhxieGV5Y).

A drawn South Park style face on every crewmate's avatar that talks, smiles, laughs (big
toothy grin, eyes squeezed shut) and shouts with its player's voice, plus a "Your avatar"
look so the crew can tell each other apart.

- `api/faces_bus.gd` (FacesBus): hangs a face on each avatar head (MultiplayerBus.avatar_added
  / avatar_head), syncs the look (event `faces.look`, join snapshot) and the 2-byte face state
  (event `faces.state`, at most 15 a second, only while it changes), face keys F5-F8, mute F9,
  push-to-talk B. Sends this player's suit colour to MultiplayerBus.set_avatar_look with no
  headgear and no visor (the person wants no hats and no face outline, just features).
- `api/face_look.gd`, `api/face_state.gd`: the look (plain data, clamped from_dict) and the
  packed face state.
- `internal/face_voice.gd`: microphone into a run-time bus "FacesMic" with a spectrum
  analyser, turned right down so nothing is heard; calibration. No audio is kept or sent.
- `internal/voice_rules.gd`: loudness and tone to mouth shape, laugh and shout detection
  (pure, tested with made-up numbers).
- `internal/face_drawing.gd`: the features, drawn in code; `face_view.gd` renders them into a
  SubViewport and wraps them round the front of a skin-coloured head (a small shader).
- Settings > Sound > "Talking face" (`voice_section.gd`), Settings > "Your avatar"
  (`avatar_page.gd`). Screenshot point `faces_mouths` (scene `faces.gallery`).

Flags: `faces`, `faces.face`, `faces.voice`. Tests: `GODOT=godot tools/run_tests.sh faces`.

Not yet: faces on walk-inside's own walker figures (that module draws its own), the slowly
turning 3D avatar on the "Your avatar" page (it shows the live face and suit colour).
