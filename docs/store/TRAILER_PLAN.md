# Trailer, screenshots and store GIFs

**Status: PROPOSED.** A plan only; nothing is captured or published yet.

## Principles

- Steam autoplays the first trailer muted on the store page and in hover previews. The first five seconds must show
  gameplay with the hero cell on screen, and every beat must read without sound.
- Gameplay footage only, captured from the real build. Pre-rendered Blender shots may appear only if labelled as
  such and never as the opening shot; the simplest rule is none.
- No other game's name, footage, music or UI. No review quotes until there are real ones.
- Title card only at the end (and optionally a two-second logo sting at the start). Wishlist call to action on the
  last card.
- 1920x1080 at 60 fps, H.264 MP4, under about 90 seconds. Steam accepts higher resolutions; 1080p60 is enough.

## Two trailers

1. **Announce teaser (cell stage, 45 to 60 s).** For the Coming Soon page. Shows only what M1 contains, plus one
   honest end card about the seven-era plan ("The first of seven eras").
2. **Gameplay trailer (later, 75 to 90 s).** After the editor, reproduction and the endless world land, and again when
   a second era exists. It replaces the teaser as the first video.

## Announce teaser shot list

Times are targets. Shots marked "needs" depend on work not in the build yet; swap them out if it is still missing at
capture time.

| # | Time | Shot | Source in the build |
| --- | --- | --- | --- |
| 1 | 0:00-0:04 | Close on the hero cell blinking in the deep blue, food drifting past; it turns to camera and swims | Pool, trailer camera (see "Capture") |
| 2 | 0:04-0:09 | Pull back to the gameplay camera: the cell weaves through shells and bacteria swarms to a plankton zone | Pool, normal play |
| 3 | 0:09-0:14 | Eating: three quick meals, "+1 point" flashes | Pool, grazer |
| 4 | 0:14-0:20 | Something larger glides under the swim plane; cut to the ambush hunter's coil tell | Pool, lair zone |
| 5 | 0:20-0:26 | The lunge, a near-miss dodge, the cell flees to shelter by the rim | Step 3 threats |
| 6 | 0:26-0:31 | Rammer puffs up and charges; a hunter-body cell takes the hit and bites back | Step 3 threats, hunter body |
| 7 | 0:31-0:37 | The start screen's three body cards (grazer, hunter, omnivore), then each body swimming | Start screen + pool |
| 8 | 0:37-0:44 | Needs the editor: a spike added, the cost preview, generation two swims away | M1 step 4 |
| 9 | 0:44-0:50 | Needs the endless world: the camera climbs as the cell grows and the pool opens up past a landmark | Endless world |
| 10 | 0:50-0:56 | End card: logo, "The first of seven eras", "Wishlist on Steam" | Title card (2D, no 3D asset) |

## Capture

- Use Godot's built-in Movie Maker mode (`--write-movie`, no new dependency). It renders every frame at a fixed rate,
  so the capture is smooth even on a slow machine, and the pool's 60 tick simulation keeps the gameplay identical.
  Record on the owner's PC or another machine with a real GPU in the Forward+ renderer; the cloud container only has
  the compatibility renderer under llvmpipe, which is fine for blocking out the edit but not for the final cut.
- Seed every take (`--seed=N`) and log the seed per shot so a shot can be re-recorded after an art change.
- Needed tooling (a dev-build task for engineering, `game/dev/`, debug builds only): a trailer camera with scripted
  dolly and zoom moves, a HUD-hide toggle, and a free-look pause. Shots 1, 4 and 9 depend on it; the rest can be
  captured with the gameplay camera and the HUD on or off.
- Editing: any editor works. DaVinci Resolve's free edition is enough. Export H.264, 1080p60, about 12 to 16 Mbit/s.

## Music and sound

- The sound department is building cell-stage ambience and effects from CC0 libraries; use those for the effects bed.
- Music: either an original commissioned track (owner budget call) or a CC0/royalty-free track whose licence allows
  trailer use on Steam and YouTube. Log the source and licence in `docs/store/` next to the cut. No unlicensed music.
- The cut must still work muted (Steam autoplays muted).

## Screenshots (Steam needs at least five, 1920x1080, gameplay only)

Capture in Forward+ on a real GPU at 1920x1080 with the HUD on in at least two, so players see how the game plays.
All of these qualify as "suitable for all ages".

1. The hero cell among shells and swarms at the gameplay camera, HUD on (energy, lineage line, points).
2. Feeding in a dense plankton zone, meal toast on screen.
3. The ambush hunter's coil tell with the threat arrow, HUD on.
4. The rammer's puff, the player turning to dodge.
5. The start screen's body cards with the cell preview (allowed: choosing a body is a unique part of the game).
6. A landmark from the endless world (once it is in the build).
7. The body editor with a cost preview (once step 4 lands).

## Store GIFs (for the long description)

Three to five short loops, 616 px wide (Steam's description column), under about 3 MB each:
eating, the coil-and-lunge dodge, the rammer charge, and later the editor and the scale-up. Cut them from the
trailer captures.
