extends SceneTree
## Look probe (micro-world plan C1, sections 5 and 6; the plan is docs/micro-world-plan.md in the
## project files). Stages fixed scenes in the real pool, saves their frames, measures CIELAB colours
## at named points and checks a look's acceptance gates. It measures what the player sees, in
## either renderer, so the micro-world look can be judged against today's, and Forward+ against
## Compatibility. It is not part of the test suite: run it at C4, C5 and C9 and whenever the look
## changes. Saves go to user://look_probe/, never the player's slot.
##
## Run it windowed, at 1920x1080 and a fixed frame rate (it refuses to run without --fixed-fps),
## from the repository root. In the cloud that means Xvfb; docs/TOOLCHAIN.md has the lavapipe setup.
##
##   Compatibility (about 2 minutes on 4 CPUs):
##     xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --audio-driver Dummy \
##       --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 1920x1080 \
##       --fixed-fps 60 --script res://tools/godot/look_probe.gd -- --out=/abs/probe_compat --look=baseline
##
##   Forward+ on lavapipe (about 10 minutes; --parity compares it with a Compatibility run):
##     VK_ICD_FILENAMES=/tmp/lvp/lvp_icd.json xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . \
##       --audio-driver Dummy --rendering-method forward_plus --rendering-driver vulkan \
##       --resolution 1920x1080 --fixed-fps 60 --script res://tools/godot/look_probe.gd -- \
##       --out=/abs/probe_fwd --look=baseline --parity=/abs/probe_compat
##
## Flags after --:
##   --out=DIR          the frames and look_probe.json (default user://look_probe/out)
##   --look=NAME        the gate set: micro (plan section 6, the default in the pool), baseline
##                      (today's look) or endless (the endless sea's, the default there)
##   --scenes=a,b       only these scenes (default every one of the world's, in its list's order)
##   --parity=DIR       another renderer's run of the same scenes: adds the parity readings and gates
##   --zoom=M           the camera distance (default the layout's, 14 m)
##   --world=MODE       pool (the default: the M1 scenes below, staged in the walled pool) or
##                      endless (the endless scenes further down, docs/s1/s1-content.md section 10)
## Exit code: 0 when every gate passes, 1 when one fails or a scene could not be staged, 2 when the
## probe cannot run (headless, no --fixed-fps, or the output folder cannot be made).
##
## Scenes. Each starts a new grazer lineage on seed 4242 with the cell holding still, plays to its
## moment with drawing off, then pauses the pool, stops time and centres the camera on the cell, so
## every frame of a scene shows the same moment:
##   lineup     both threats, plankton, three carrion pieces and the cell in the centre zone, AI frozen
##   tell       the ambush hunter at lair_se about 0.8 s into its 1.2 s tell on the cell
##   puff       the rammer of terr_n_a 0.65 s into its puff before a charge at the cell
##   rim_north  the cell 4 m from the north rim, facing it, AI frozen
##   rim_south  the cell 5 m from the south rim, facing it, AI frozen
##   starving   the starving (grey) cell at the spawn, AI frozen
##   hud        the starving cell (banner and food arrow) with a rammer near and the hurt vignette
##              at its peak, AI frozen
##   sunlit     the cell in the middle of the z_s plankton zone, in its sunlit patch, AI frozen
##   shelter    the sheltered cell over the brightest shaft of z_s's patch, its rim at mid pulse,
##              AI frozen
##
## Frames, in --out: <scene>.png is what the player sees; <scene>_fluid.png is the same moment with
## every body, food item, rock, world label and the 2D layer hidden, so it shows what lies behind
## them. tell and puff add <scene>_nolane.png (the lane hidden), <scene>_decor.png and
## <scene>_decor_nolane.png (a pale decor stand-in under the lane, with and without it) and
## <scene>_marker.png (the "!" popped over the telling creature, the stand-in hidden); hud adds
## <scene>_vignette.png (the 3D frame and the vignette alone) and <scene>_world.png (no 2D layer).
## sunlit adds <scene>_nopatch.png (the fluid frame with the zone lights hidden) and
## <scene>_ambush.png (an ambush hunter let in over the patch's brightest point). shelter adds
## <scene>_bare.png (the same moment with the rim off) and <scene>_unlit.png (the fluid frame with
## the zone lights hidden). When art's ambience is mounted, rim_north adds <scene>_wall.png (the
## fluid frame with the ambience hidden too).
## <scene>_points.png outlines every sampled region in yellow.
##
## Readings, in look_probe.json under scenes.<scene>.readings: a point is the per-channel median of
## its sRGB pixels as {"hex", "L", "a", "b", "C", "h"} (CIE76, D65; h in degrees) plus "max_channel"
## (0 to 255). Every scene has cell (the inner 55% of the cell's disc), cell_behind (the fluid frame
## there), fluid_near_cell (the fluid frame's centre third), cell_dL (|L* of cell - L* of
## fluid_near_cell|), fluid_threat_hue_gap (degrees of LAB hue between fluid_near_cell and the threat
## colour), fluid_top, fluid_bottom, fluid_corner_tl/tr/bl/br, fluid_corners_min_L, glow_dL
## (fluid_near_cell L* minus the corners' mean: the depth glow), creatures (each on-screen body
## against the fluid behind it) and render_info. lineup adds plankton and carrion (each on-screen item
## clear of bodies and HUD panels; hue span, highest channel, hue gap from the threat colour) and
## ambush_dL (the ambush hunter's body against what lies behind it, the least of any on screen); tell
## and puff add lane (the outline's largest |dL*| against the same pixels without the lane, across
## the lane's edge at 30, 50 and 70% of its length on both sides, skipping places a body covers;
## over the fluid and over the decor stand-in; and the L* the sunlit patches add under its edge)
## and marker (the "!"'s outline and glyph pixels, the fluid behind them and their WCAG contrast
## ratios); rim_north adds skirt (L* down the north wall from
## 1 m to 30 m deep, and its largest step between neighbouring samples, read without art's decor);
## hud adds vignette (the four
## corners with the vignette alone), vignette_behind and vignette_dE; sunlit adds patch (the zone's
## light: L* of the fluid frame against the same without the zone lights, out from the zone's centre
## on the patches' plane) and ambush (that hunter's body against what lies behind it, and the patch
## point it covers); shelter adds shelter (the rim: the cell's outer band, SHELTER_BAND of its radius,
## against the same pixels unsheltered, and against the fluid just outside it; and the L* the patch
## adds behind the cell). With --parity every scene adds
## parity: the median CIE76 between the two runs over the whole frame, the fluid frame and the cell.
##
## Endless scenes (--world=endless, ENDLESS_SCENES). Each starts the same way, then freezes the AI,
## moves the cell to an absolute place in the sea (debug_teleport_abs: the view set there loads and
## its food fills) and plays START_FRAMES there, so its creatures finish fading in:
##   reef         the densest knot of shells of the reef tile nearest the origin, facing north: the
##                cell REEF_SOUTH_TM south of the centroid of the shell with the most others within
##                REEF_KNOT_TM and those others (a reef tile keeps its shells round its zones, not at
##                its centre, so the content doc's "6 tm south of the centre" frames open water)
##   landmark     ANCHOR_SOUTH_TM south of the nearest landmark anchor that is not a shed husk
##   husk         HUSK_GAP_TM south of the giant husk's southmost collider, at the giant husk nearest
##                the origin, facing north: the husk side-on from the south (build plan B-30)
##   shed_husk    ANCHOR_SOUTH_TM south of the nearest landmark_shed_husk anchor (B-30)
##   markers      MARKERS_AT facing east, the checkpoint at home: the arrow home and the column's pip
##   rebase_pair  the reef moment, paused, before and after a dev rebase by one chunk east: shells
##                all round, so the world-placed layers show if they do not follow (the content doc
##                stages it at the markers spot, open water where only world-rebuilt things show)
## Their frames: reef adds <scene>_norocks.png (every shell hidden); landmark, husk and shed_husk add
## <scene>_nopiece.png (that piece hidden); markers adds <scene>_nomarkers.png (both markers hidden)
## and <scene>_nooverlay.png (the HUD's world overlay hidden); rebase_pair saves frame A as
## <scene>.png, A shot again as <scene>_still.png and frame B as <scene>_after.png.
## Their readings: a piece's pixels are those it draws, where the frame differs from the same moment
## without it by more than SILHOUETTE_CHANGE in a channel, read against the fluid frame there:
## fluid_dL between their median and the fluid's, and fluid_dL_px, the median of each pixel's own
## |dL*|. A hue gap is the LAB hue's distance from the food or threat colour, 180 for a colour under
## ACHROMATIC_C chroma (it has no hue to confuse; the look rule's exemption). Every endless scene has
## staged (where it was staged and what it frames) and the common readings above. reef adds shells
## (each shell on screen clear of HUD panels, nearest the centre first, with its silhouette in its
## projected box; food_gap_min, threat_gap_min, fluid_dL_min, fluid_dL_px_min); landmark, husk and
## shed_husk add the piece's silhouette in its projected box (silhouette, silhouette_behind, pixels,
## share, fluid_dL, fluid_dL_px, food_gap, threat_gap); markers adds arrow_L (L* of the arrow's
## centre, ARROW_DISC_PX round its mesh's centre), arrow (its silhouette), arrow_state, and
## pip_present (1 when the column's pip changes pixels where the overlay draws it) with pip;
## rebase_pair adds median_dE and p99_dE (CIE76 between A and B over every PARITY_STRIDE-th pixel)
## and still_median_dE and still_p99_dE (A against A again: what drawing twice changes by itself).

const MAIN_SCENE := "res://game/scenes/main.tscn"
const SLOT := "user://look_probe/slot.json"
const DEFAULT_OUT := "user://look_probe/out"
const BODY := "grazer"
const SEED := 4242
## The M1 pool's scenes, every one with --world=pool.
const POOL_SCENES: Array[String] = ["lineup", "tell", "puff", "rim_north", "rim_south", "starving", "hud", "sunlit", "shelter"]
## The endless sea's scenes (docs/s1/s1-content.md section 10), every one with --world=endless.
const ENDLESS_SCENES: Array[String] = ["reef", "landmark", "husk", "shed_husk", "markers", "rebase_pair"]
## Every scene the probe can stage: POOL_SCENES, then ENDLESS_SCENES.
const SCENES: Array[String] = ["lineup", "tell", "puff", "rim_north", "rim_south", "starving", "hud", "sunlit", "shelter",
	"reef", "landmark", "husk", "shed_husk", "markers", "rebase_pair"]
## The world each gate set measures.
const LOOK_WORLDS := {"micro": "pool", "baseline": "pool", "endless": "endless"}
const SIZE := Vector2i(1920, 1080)       ## the gates' thresholds were measured at this size
const START_FRAMES := 30                 ## frames of a new run before staging (the fade-in is 0.3 s)
const FIRST_SETTLE := 2                  ## frames drawn before a moment's first capture...
const SETTLE := 1                        ## ...and before each later capture of it
const TELL_WAIT_FRAMES := 3600
const TELL_FRAMES := 50                  ## into the ambush tell when it is shot (of 72)
const PUFF_FRAMES := 40                  ## into the rammer's puff when it is shot (of 72)
const CARRION_SETTLE_FRAMES := 45        ## new carrion sinks and grows in over 0.6 s
const STARVE_FRAMES := 45                ## the cell's starving tint fades in over 0.4 s
const CELL_CORE := 0.55                  ## share of the cell's radius sampled (clear of its membrane)
const BODY_CORE := 0.5                   ## the same for a creature
const FOOD_CORE := 0.6                   ## the same for a food item's hue (its whole disc for clipping)
const COVER_MARGIN := 1.3                ## a body covers this many of its radii on screen
const MAX_FOOD_ITEMS := 12
const FOOD_HEX := "CFE86A"               ## docs/art/ART_DIRECTION.md: food-only glow...
const THREAT_HEX := "D9466B"             ## ...and threat-only pink
## The decor stand-in under a lane: the palest decor the ambience contract allows (luminance ×
## alpha = 0.12, plan section 7), a camera-facing plane at the top of the midground band, fogged.
const DECOR_COLOR := Color(0.85, 0.92, 1.0)
const DECOR_ALPHA := 0.147
const DECOR_Y := -3.0
const LANE_FRACTIONS: Array[float] = [0.3, 0.5, 0.7]
const LANE_SCAN_IN_M := 0.45             ## the outline scan runs from this far inside the lane's edge...
const LANE_SCAN_OUT_M := 0.2             ## ...to this far outside it...
const LANE_SCAN_STEPS := 24              ## ...in this many steps
const LANE_POINTS_NEEDED := 3            ## plan section 6: "dL* ≥ 15 at 3 points"
const RIM_WALL_M := 38.75                ## the rim's skirt radius (plan section 3)
const SKIRT_TOP_Y := -1.0
const SKIRT_BOTTOM_Y := -30.0
const SKIRT_STEP_M := 0.5
const SKIRT_BOX_PX := 5
const PARITY_STRIDE := 4
const MARKER_BOX_PX := 60                ## the "!" marker is measured within this many px of its anchor...
const MARKER_CHANGE := 0.1               ## ...where it changes a channel by more than this
const SUNLIT_ZONE := "z_s"               ## the sunlit scene's zone: radius 6 m, no rock or lair in view
const PATCH_FRACTIONS: Array[float] = [0.0, 0.25, 0.5, 0.75, 0.88, 1.0, 1.15, 1.3]   ## zone radii out...
const PATCH_DIRECTIONS := 16             ## ...along this many directions, on the patches' plane
const PATCH_BOX_PX := 9
## The shelter scene's cell: in front of the brightest shaft of SUNLIT_ZONE's patch (the sunlit
## scene's patch_point, 1.0 zone radii out at 202.5 degrees), moved 1.75 m toward the camera, which
## is how far the patch 2.5 m down lies behind the view centre at the camera's 55 degree pitch.
const SHELTER_SPOT := Vector2(-5.5, 21.45)
const SHELTER_FRAMES := 30               ## the shelter rim fades in over 0.3 s
const SHELTER_BAND := Vector2(0.6, 1.3)  ## the rim: the cell's own pixels this far out (radii)...
const SHELTER_OUTSIDE := Vector2(1.3, 1.6)    ## ...and the fluid just outside the cell
const BOX_COLOR := Color(1.0, 0.95, 0.0)
# The endless scenes (absolute positions in tm; at S1's size 1 an am is a tm).
const REEF_KNOT_TM := 8.0                ## the reef scene frames the shell with most others this near...
const REEF_SOUTH_TM := 2.0               ## ...with the cell this far south of their centroid
const ANCHOR_SOUTH_TM := 8.0             ## the landmark scenes' cell, south of the anchor
const HUSK_GAP_TM := 4.4                 ## the husk scene's cell, south of the husk's southmost collider
const MARKERS_AT := Vector2(300.0, 9.0)  ## the markers scene's cell, facing east
const SHED_HUSK := "landmark_shed_husk"
const SEARCH_TILES := 12                 ## the nearest reef tile is looked for this many tiles out...
const SEARCH_CHUNKS := 12                ## ...and the nearest anchors and rare places this many chunks out
const SHELL_ON_SCREEN := 0.5            ## a shell is read when this share of its projected box is on screen...
const SHELL_PIXELS_NEEDED := 100         ## ...and it draws at least this many pixels there
const SILHOUETTE_CHANGE := 0.03          ## a piece draws a pixel it changes by more than this in a channel
const ACHROMATIC_C := 5.0                ## a colour under this chroma has no hue (the look rule's exemption)
const ARROW_DISC_PX := 3.0
const REBASE_BY := Vector2i(1, 0)        ## the rebase pair's dev rebase, in chunks

## The acceptance gates by look. A gate reads the number at `path` in the readings ("lineup.cell.h")
## and passes when it lies in [min, max] (either end may be left out); a reading that is missing
## fails. A "parity" gate runs only with --parity, and a gate on a scene that did not run is skipped.
##   micro: plan section 6 (PROPOSED), plus the depth glow check of plan section 10, risk 1,
##   section 3's 90 degrees of LAB hue between the fluid and the threat pink, read on screen, and
##   the sunlit patches' gates (docs/DECISIONS.md, "Microscopic world look"): seen, broken into
##   shafts, under the tell's lane, and never cutting the cell or an ambush hunter under 15 dL*; and
##   plan section 4's shelter rim against the zone light.
##   baseline: today's look (m1-threats at ecb1eee) in both renderers, with margins (docs/DECISIONS.md,
##   "Microscopic world look"), so the probe itself can be checked on today's build. Its "fluid" is
##   the teal floor. It has no skirt or plankton clipping gate: there is no skirt yet (those samples
##   land on the floor's caustics), and the plankton's sunlit tops reach 255 in both renderers.
##   endless: the endless sea (docs/s1/s1-content.md section 10, PROPOSED there; build plan Q15 has
##   T5.6 set them from its measurement): shells, landmarks and the husks keep clear of food and
##   threat on screen, after light and fog (20 degrees; the albedo rule is 25) and stand out from the
##   fluid, the arrow home is light, the column's pip shows, and a rebase never shows (G10).
const GATES := {
	"micro": [
		{"id": "cell_hue", "path": "lineup.cell.h", "min": 30.0, "max": 50.0, "what": "coral cell hue (LAB h)"},
		{"id": "cell_contrast", "path": "lineup.cell_dL", "min": 15.0, "what": "cell against the fluid, centre third (|dL*|)"},
		{"id": "fluid_value", "path": "lineup.fluid_near_cell.L", "min": 26.0, "max": 36.0, "what": "fluid near the cell (L*)"},
		{"id": "fluid_hue", "path": "lineup.fluid_near_cell.h", "min": 268.0, "max": 288.0, "what": "fluid near the cell (h)"},
		{"id": "fluid_chroma", "path": "lineup.fluid_near_cell.C", "min": 25.0, "what": "fluid near the cell (C*)"},
		{"id": "fluid_threat_gap", "path": "lineup.fluid_threat_hue_gap", "min": 90.0, "what": "fluid near the cell, LAB hue away from the threat colour (degrees)"},
		{"id": "fluid_corners", "path": "lineup.fluid_corners_min_L", "min": 15.0, "what": "darkest fluid corner (L*)"},
		{"id": "depth_glow", "path": "lineup.glow_dL", "min": 5.0, "what": "centre field lighter than the corners (dL*)"},
		{"id": "lane_fluid_tell", "path": "tell.lane.over_fluid_min_dL", "min": 15.0, "what": "ambush lane outline over the fluid (|dL*|, 3 points)"},
		{"id": "lane_decor_tell", "path": "tell.lane.over_decor_min_dL", "min": 15.0, "what": "ambush lane outline over pale decor (|dL*|, 3 points)"},
		{"id": "lane_fluid_puff", "path": "puff.lane.over_fluid_min_dL", "min": 15.0, "what": "rammer lane outline over the fluid (|dL*|, 3 points)"},
		{"id": "lane_decor_puff", "path": "puff.lane.over_decor_min_dL", "min": 15.0, "what": "rammer lane outline over pale decor (|dL*|, 3 points)"},
		{"id": "plankton_hue_low", "path": "lineup.plankton.h_min", "min": 110.0, "what": "plankton hue, lowest item (h)"},
		{"id": "plankton_hue_high", "path": "lineup.plankton.h_max", "max": 145.0, "what": "plankton hue, highest item (h)"},
		{"id": "plankton_clip", "path": "lineup.plankton.max_channel", "max": 254.0, "what": "plankton never clips (highest channel)"},
		{"id": "carrion_hue", "path": "lineup.carrion.threat_hue_gap", "min": 15.0, "what": "carrion hue away from the threat colour (degrees)"},
		{"id": "vignette_hue", "path": "hud.vignette.h", "min": 15.0, "max": 45.0, "what": "hurt vignette outer band (h)"},
		{"id": "marker_outline", "path": "tell.marker.outline_contrast", "min": 3.0, "what": "the \"!\" marker's outline against the fluid behind it (WCAG contrast)"},
		{"id": "starving_contrast", "path": "starving.cell_dL", "min": 10.0, "what": "starving cell against the fluid (|dL*|)"},
		{"id": "ambush_contrast", "path": "lineup.ambush_dL", "min": 15.0, "what": "ambush hunter on the centre zone's lit band, against what lies behind it (|dL*|)"},
		{"id": "lane_on_patch", "path": "tell.lane.patch_lift_max_dL", "min": 2.0, "what": "the tell's lane lies over a sunlit patch, so its lane gates hold there (dL* the patch adds under its edge)"},
		{"id": "patch_visible", "path": "sunlit.patch.lift_max_dL", "min": 5.0, "what": "a sunlit patch lifts the fluid where it is brightest (dL*)"},
		{"id": "patch_shafts", "path": "sunlit.patch.ring_min_share", "max": 0.5, "what": "the patch's light is broken into shafts, not an even ring round a target (least lift over the most at its brightest radius)"},
		{"id": "patch_ambush", "path": "sunlit.ambush.dL", "min": 15.0, "what": "ambush hunter over the brightest point of a sunlit patch (|dL*|)"},
		{"id": "sunlit_cell", "path": "sunlit.cell_dL", "min": 15.0, "what": "cell against the fluid in the middle of a sunlit patch (|dL*|)"},
		{"id": "shelter_rim", "path": "shelter.shelter.rim_lift_p90_dL", "min": 5.0, "what": "the shelter rim at mid pulse, over a sunlit patch, lifts the brightest tenth of the cell's edge (dL*)"},
		{"id": "skirt_edge", "path": "rim_north.skirt.max_step_dL", "max": 6.0, "what": "no hard lower edge on the rim wall (largest dL* step)"},
		{"id": "parity_fluid", "path": "lineup.parity.fluid_dE", "max": 2.0, "parity": true, "what": "renderer parity, fluid (median CIE76)"},
		{"id": "parity_cell", "path": "lineup.parity.cell_dE", "max": 2.0, "parity": true, "what": "renderer parity, cell (median CIE76)"},
	],
	# Today's readings, Compatibility | Forward+ (docs/TOOLCHAIN.md): each range holds both.
	"baseline": [
		{"id": "cell_hue", "path": "lineup.cell.h", "min": 30.0, "max": 50.0, "what": "coral cell hue (LAB h; 42.1 | 41.3)"},
		{"id": "cell_contrast", "path": "lineup.cell_dL", "max": 8.0, "what": "cell against the floor, centre third: it reads by hue, not value (|dL*|; 2.4 | 3.6)"},
		{"id": "fluid_value", "path": "lineup.fluid_near_cell.L", "min": 36.0, "max": 54.0, "what": "teal floor near the cell (L*; 42.4 | 47.5)"},
		{"id": "fluid_hue", "path": "lineup.fluid_near_cell.h", "min": 198.0, "max": 220.0, "what": "teal floor near the cell (h; 206.3 | 212.8)"},
		{"id": "fluid_chroma", "path": "lineup.fluid_near_cell.C", "min": 16.0, "max": 31.0, "what": "teal floor near the cell (C*; 22.6 | 24.3)"},
		{"id": "fluid_corners", "path": "lineup.fluid_corners_min_L", "min": 40.0, "max": 62.0, "what": "darkest floor corner (L*; 48.4 | 55.2)"},
		{"id": "depth_glow", "path": "lineup.glow_dL", "min": -14.0, "max": -3.0, "what": "centre darker than the corners, where the floor deepens (dL*; -7.7 | -9.2)"},
		{"id": "lane_fluid_tell", "path": "tell.lane.over_fluid_min_dL", "min": 1.0, "max": 12.0, "what": "ambush lane outline over the floor (|dL*|, 3 points; 8.0 | 3.0)"},
		{"id": "lane_decor_tell", "path": "tell.lane.over_decor_min_dL", "min": 1.0, "max": 12.0, "what": "ambush lane outline; the decor stand-in lies under the floor (|dL*|; 8.0 | 3.0)"},
		{"id": "lane_fluid_puff", "path": "puff.lane.over_fluid_min_dL", "min": 1.0, "max": 12.0, "what": "rammer lane outline over the floor (|dL*|, 3 points; 6.4 | 2.8)"},
		{"id": "lane_decor_puff", "path": "puff.lane.over_decor_min_dL", "min": 1.0, "max": 12.0, "what": "rammer lane outline; the decor stand-in lies under the floor (|dL*|; 6.4 | 2.8)"},
		{"id": "plankton_hue_low", "path": "lineup.plankton.h_min", "min": 100.0, "max": 125.0, "what": "plankton hue, lowest item (h; 108.6 | 117.8)"},
		{"id": "plankton_hue_high", "path": "lineup.plankton.h_max", "min": 129.0, "max": 145.0, "what": "plankton hue, highest item (h; 138.2 | 136.6)"},
		{"id": "carrion_hue", "path": "lineup.carrion.threat_hue_gap", "min": 10.0, "max": 27.0, "what": "carrion hue away from the threat colour (degrees; 18.6 | 15.1)"},
		{"id": "vignette_hue", "path": "hud.vignette.h", "min": 243.0, "max": 270.0, "what": "hurt vignette outer band, blue-grey over teal (h; 261.2 | 254.2)"},
		{"id": "starving_contrast", "path": "starving.cell_dL", "max": 10.0, "what": "starving cell against the floor (|dL*|; 5.8 | 3.7)"},
		{"id": "parity_fluid", "path": "lineup.parity.fluid_dE", "max": 10.0, "parity": true, "what": "renderer parity, floor (median CIE76; 6.7)"},
		{"id": "parity_cell", "path": "lineup.parity.cell_dE", "max": 10.0, "parity": true, "what": "renderer parity, cell (median CIE76; 7.0)"},
	],
	# Measured at T5.6 (seed 4242, 1920x1080, zoom 14), Compatibility | Forward+ (lavapipe); the
	# renderers agree within 0.1 CIE76 over the frame. Where the content doc's PROPOSED threshold
	# held it is kept; where it did not, the gate is pinned about a fifth under the lower reading
	# (build plan Q15) and the content doc's number is given. Contrast is read per pixel (the median
	# of each drawn pixel's |dL*| against the fluid behind it): the kit's pieces are tall, lit on top
	# and fluid-tinted on their sides, so the median of a silhouette can match the fluid's while its
	# parts stand well apart (the shed husk: 0.8 | 1.1 between the medians, 5.5 | 5.8 per pixel).
	"endless": [
		{"id": "reef_food_gap", "path": "reef.shells.food_gap_min", "min": 20.0, "what": "reef shells, LAB hue away from the food colour (degrees, the least on screen; 137.8 | 137.8)"},
		{"id": "reef_threat_gap", "path": "reef.shells.threat_gap_min", "min": 20.0, "what": "reef shells, LAB hue away from the threat colour (degrees, the least on screen; 89.8 | 89.8)"},
		{"id": "reef_contrast", "path": "reef.shells.fluid_dL_px_min", "min": 5.0, "what": "reef shells against the fluid behind them (|dL*| per pixel, the least on screen; 6.3 | 6.3, a diatom disc seen side-on; PROPOSED 8)"},
		{"id": "landmark_contrast", "path": "landmark.fluid_dL_px", "min": 7.5, "what": "the nearest landmark against the fluid (|dL*| per pixel; 9.6 | 9.8; PROPOSED 10)"},
		{"id": "landmark_food_gap", "path": "landmark.food_gap", "min": 20.0, "what": "the nearest landmark, LAB hue away from the food colour (degrees; 171.2 | 171.2)"},
		{"id": "landmark_threat_gap", "path": "landmark.threat_gap", "min": 20.0, "what": "the nearest landmark, LAB hue away from the threat colour (degrees; 85.5 | 85.5)"},
		{"id": "husk_contrast", "path": "husk.fluid_dL_px", "min": 6.0, "what": "the giant husk side-on from the south against the fluid (|dL*| per pixel; 7.5 | 7.5; PROPOSED 10)"},
		{"id": "husk_food_gap", "path": "husk.food_gap", "min": 20.0, "what": "the giant husk never reads as food: LAB hue away from the food colour (degrees; 165.8 | 165.8)"},
		{"id": "husk_threat_gap", "path": "husk.threat_gap", "min": 20.0, "what": "the giant husk, LAB hue away from the threat colour (degrees; 90.9 | 90.9)"},
		{"id": "shed_husk_contrast", "path": "shed_husk.fluid_dL_px", "min": 4.5, "what": "the shed husk landmark against the fluid (|dL*| per pixel; 5.5 | 5.8; PROPOSED 10)"},
		{"id": "shed_husk_food_gap", "path": "shed_husk.food_gap", "min": 20.0, "what": "the shed husk never reads as food: LAB hue away from the food colour (degrees; 165.0 | 165.0)"},
		{"id": "shed_husk_threat_gap", "path": "shed_husk.threat_gap", "min": 20.0, "what": "the shed husk, LAB hue away from the threat colour (degrees; 91.7 | 91.7)"},
		{"id": "arrow_value", "path": "markers.arrow_L", "min": 75.0, "what": "the arrow home's centre (L*; 99.8 | 99.8)"},
		{"id": "column_pip", "path": "markers.pip_present", "min": 1.0, "max": 1.0, "what": "the column's pip shows while the column is off screen (1 | 1)"},
		{"id": "rebase_median", "path": "rebase_pair.median_dE", "max": 1.0, "what": "a rebase never shows: frame B against frame A (median CIE76; 0.0 | 0.0)"},
		{"id": "rebase_p99", "path": "rebase_pair.p99_dE", "max": 5.0, "what": "a rebase never shows: frame B against frame A (99th percentile CIE76; 0.0 | 0.0)"},
	],
}

## Swims nowhere: the cell holds still while a scene plays to its moment.
class Still:
	extends RefCounted

	func next_intent(_sim: PoolSim) -> SimIntent:
		return SimIntent.new()

var main: Main
var pool: PoolScene
var sim: PoolSim
var out_dir := ""
var look := "micro"
var parity_dir := ""
var zoom := 0.0
## The world every scene runs in (RunFlags.world): "pool" unless --world says otherwise, so the M1
## scenes stage in the walled pool they were measured in.
var world := "pool"
## Every sim event of the current run, in order.
var events: Array[Dictionary] = []
## scene -> {"frames": {variant: file}, "readings": {...}, "error": text}
var results := {}
## Regions sampled in the current scene, outlined in <scene>_points.png.
var _boxes: Array[Rect2i] = []
var _decor: MeshInstance3D
## Where an endless scene was staged and what it frames (its readings' "staged"); the piece a
## landmark scene reads is staged["id"].
var _staged := {}
## The endless sea's anchors, rare places and set-piece colliders round the origin (_sea()).
var _sea_cache := {}


func _initialize() -> void:
	RenderingServer.render_loop_enabled = false
	var scenes: Array[String] = []
	var look_given := false
	out_dir = DEFAULT_OUT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--look="):
			look = arg.trim_prefix("--look=")
			look_given = true
		elif arg.begins_with("--scenes="):
			scenes.assign(Array(arg.trim_prefix("--scenes=").split(",")))
		elif arg.begins_with("--parity="):
			parity_dir = arg.trim_prefix("--parity=")
		elif arg.begins_with("--zoom="):
			zoom = float(arg.trim_prefix("--zoom="))
		elif arg.begins_with("--world="):
			world = arg.trim_prefix("--world=")
	if not look_given and world == "endless":
		look = "endless"
	if scenes.is_empty():
		scenes = scenes_for(world)
	var problem := _setup_problem(scenes)
	if problem.is_empty():
		root.size = SIZE
		# --fixed-fps leaves no trace in the arguments a script sees; it shows as an exact frame step.
		for i in 2:
			await process_frame
		if not is_equal_approx(root.get_process_delta_time(), 1.0 / Engine.physics_ticks_per_second):
			problem = "pass --fixed-fps %d, so every run plays the same frames" % Engine.physics_ticks_per_second
		elif root.size != SIZE:
			push_warning("The window is %s, not %s, where the gates were measured." % [root.size, SIZE])
	if not problem.is_empty():
		printerr("Look probe cannot run: %s" % problem)
		quit(2)
		return
	print("Look probe: %s gates, %s (%s), scenes %s" % [look, RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name(), ", ".join(scenes)])
	for scene in scenes:
		results[scene] = {"frames": {}, "readings": {}, "error": ""}
		await _fresh_run()
		var staged := await _stage(scene)
		if not _staged.is_empty():
			results[scene].readings.staged = _staged.duplicate()
		if not staged:
			results[scene].error = "could not stage the scene"
			printerr("Look probe: could not stage %s" % scene)
			continue
		await _freeze()
		await _shoot(scene)
		_thaw()
	var gates := evaluate(GATES[look], _readings(), not parity_dir.is_empty())
	var failed := 0
	for g: Dictionary in gates:
		print("%s %-18s %s = %s  (%s)" % [g.status.to_upper(), g.id, g.path, str(g.value), g.what])
		if g.status == "fail":
			failed += 1
	var staged_all := results.values().all(func(r: Dictionary) -> bool: return r.error.is_empty())
	_write_report(gates, failed)
	print("Look probe: %d gates, %d failed. Report: %s" % [gates.size(), failed, ProjectSettings.globalize_path(out_dir.path_join("look_probe.json"))])
	quit(0 if failed == 0 and staged_all else 1)


## Why the probe cannot run here, or "".
func _setup_problem(scenes: Array[String]) -> String:
	if DisplayServer.get_name() == "headless":
		return "it needs a real renderer (run it under xvfb-run, not --headless)"
	if not GATES.has(look):
		return "--look must be one of %s" % ", ".join(GATES.keys())
	var own := scenes_for(world)
	if own.is_empty():
		return "--world must be pool or endless"
	if LOOK_WORLDS.get(look, world) != world:
		return "--look=%s measures the %s world: pass --world=%s" % [look, LOOK_WORLDS[look], LOOK_WORLDS[look]]
	for scene in scenes:
		if not own.has(scene):
			return "there is no %s scene %s (scenes: %s)" % [world, scene, ", ".join(own)]
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir)) != OK:
		return "cannot make %s" % out_dir
	return ""


# --- Runs and moments ----------------------------------------------------------------------------

## A new grazer lineage on SEED in a fresh pool, the cell holding still and unsheltered,
## START_FRAMES in.
func _fresh_run() -> void:
	if main == null:
		main = (load(MAIN_SCENE) as PackedScene).instantiate()
		root.add_child(main)
		await process_frame
		main.flags.world = world
		main.open_session(SLOT)
	for path in [SLOT, SLOT + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.intent_provider = Still.new()
	events.clear()
	_decor = null
	_staged = {}
	main.start_new(BODY, SEED)
	pool = main.pool
	sim = pool.sim
	pool.pause_on_focus_loss = false
	pool.sim_event.connect(func(e: Dictionary): events.append(e))
	# No shelter: its rim would tint the cell and its chip show in the HUD.
	sim.grace_until = sim.tick
	await _play(START_FRAMES)


## Plays `n` frames without drawing them.
func _play(n: int) -> void:
	for i in n:
		await process_frame


## Plays until `id` starts a tell on the cell (at most `limit` frames). Returns the event or {}.
func _play_to_tell(id: String, limit: int) -> Dictionary:
	for i in limit:
		for e in events:
			if e.type == "creature_tell" and e.get("id") == id and e.get("target") == CreatureField.PLAYER_ID:
				return e
		await process_frame
	return {}


## Stops the moment: the pool pauses (its views show the current tick), time stands still, and the
## camera centres on the cell at the probe's zoom.
func _freeze() -> void:
	pool.set_paused(true)
	Engine.time_scale = 0.0
	await _play(1)
	if zoom > 0.0:
		pool.camera.distance = clampf(zoom, pool.camera.zoom_min, pool.camera.zoom_max)
	pool.camera.snap_to(pool.cell_view.position)


func _thaw() -> void:
	Engine.time_scale = 1.0
	RenderingServer.render_loop_enabled = false


## Draws the moment as it is now and returns the frame; `frames` are drawn, the last one kept.
func _capture(frames := SETTLE) -> Image:
	RenderingServer.render_loop_enabled = true
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	RenderingServer.render_loop_enabled = false
	img.convert(Image.FORMAT_RGB8)
	return img


func _save(scene: String, variant: String, img: Image) -> void:
	var file := scene + ("" if variant.is_empty() else "_" + variant) + ".png"
	var err := img.save_png(out_dir.path_join(file))
	if err != OK:
		printerr("Look probe could not save %s: %s" % [file, error_string(err)])
	results[scene].frames[variant if not variant.is_empty() else "full"] = file


## Shows or hides what lies in front of the fluid: the cell, creatures, food, rocks, world labels
## and the 2D layer (HUD, target ring, starving arrow); in the endless sea its landmarks, rare set
## pieces and way-markers too.
func _show_gameplay(on: bool) -> void:
	var nodes: Array[Node3D] = [pool.cell_view, pool.creature_layer, pool.plankton_view, pool.carrion_view, pool.rocks, pool.feedback]
	if pool.is_endless():
		nodes.append_array([pool.landmarks, pool.markers])
	for node in nodes:
		node.visible = on
	pool.ui.visible = on


## The full frame and the fluid frame of the moment, saved, plus the readings every scene has.
func _shoot_common(scene: String) -> Array[Image]:
	_boxes.clear()
	var full := await _capture(FIRST_SETTLE)
	var info := _render_info()
	_show_gameplay(false)
	var fluid := await _capture()
	_show_gameplay(true)
	_save(scene, "", full)
	_save(scene, "fluid", fluid)
	var r: Dictionary = results[scene].readings
	r.render_info = info
	r.merge(_common_readings(full, fluid))
	r.creatures = _creature_readings(full, fluid)
	if not parity_dir.is_empty():
		r.parity = _parity_readings(scene, full, fluid)
	return [full, fluid]


# --- Scenes: staging ---------------------------------------------------------------------------

## Plays the scene to its moment. Returns false when it cannot.
func _stage(scene: String) -> bool:
	match scene:
		"lineup":
			return await _stage_lineup()
		"tell":
			return await _stage_tell()
		"puff":
			return await _stage_puff()
		"rim_north":
			return await _stage_rim(Vector2(3.0, -35.0), -PI / 2.0)
		"rim_south":
			return await _stage_rim(Vector2(-3.0, 34.5), PI / 2.0)
		"starving":
			return await _stage_starving()
		"hud":
			return await _stage_hud()
		"sunlit":
			return await _stage_sunlit()
		"shelter":
			return await _stage_shelter()
		"reef":
			return await _stage_reef()
		"landmark":
			return await _stage_anchor(false)
		"shed_husk":
			return await _stage_anchor(true)
		"husk":
			return await _stage_husk()
		"markers":
			_staged = {"at_tm": [MARKERS_AT.x, MARKERS_AT.y], "checkpoint_am": Array(sim.world.checkpoint_am) if sim.world != null else []}
			return await _stage_at(MARKERS_AT, 0.0)
		"rebase_pair":
			return await _stage_reef()
	return false


## Dev creatures, since the sim keeps every site's creature on its leash.
func _stage_lineup() -> bool:
	sim.debug_set_ai_frozen(true)
	var center := Vector2(0.0, 1.5)
	if not sim.debug_spawn_creature("ambush_hunter", center + Vector2(-4.2, -1.0), -PI / 2.0):
		return false
	if not sim.debug_spawn_creature("rammer", center + Vector2(4.4, -2.2), -PI / 2.0):
		return false
	for i in 3:
		var p := center + Vector2(0.5, 3.4) + Vector2.from_angle(TAU * i / 3.0 + 0.4) * 0.9
		if sim.arena.is_clear(p, sim.carrion.item_radius):
			sim.carrion.spawn(p, "debug")
	if not sim.debug_teleport(center, -PI / 2.0):
		return false
	await _play(_whole_frames(CARRION_SETTLE_FRAMES))
	return true


func _stage_tell() -> bool:
	var hunter := _creature_at("lair_se")
	if hunter == null:
		return false
	sim.grace_until = sim.tick
	hunter.brain.ignore_all_until = sim.tick
	var front: Vector2 = hunter.motion.position + Vector2.from_angle(hunter.motion.heading) * 2.75
	if not sim.debug_teleport(front, hunter.motion.heading):
		return false
	if (await _play_to_tell(hunter.id, TELL_WAIT_FRAMES)).is_empty():
		return false
	await _play(TELL_FRAMES)
	return true


func _stage_puff() -> bool:
	var rammer := _creature_at("terr_n_a")
	if rammer == null or not rammer.brain.territory_center.is_finite():
		return false
	sim.grace_until = sim.tick
	rammer.brain.ignore_all_until = sim.tick
	if not sim.debug_teleport(rammer.brain.territory_center + Vector2(1.0, 4.5), -1.9):
		return false
	if (await _play_to_tell(rammer.id, TELL_WAIT_FRAMES)).is_empty():
		return false
	await _play(PUFF_FRAMES)
	return true


## The cell near the rim at `at`, facing it.
func _stage_rim(at: Vector2, heading: float) -> bool:
	sim.debug_set_ai_frozen(true)
	if not sim.debug_teleport(at, heading):
		return false
	await _play(20)
	return true


func _stage_starving() -> bool:
	sim.debug_set_ai_frozen(true)
	if not sim.debug_teleport(sim.layout.spawn, -PI / 2.0) or not sim.debug_set_energy(0.0):
		return false
	await _play(STARVE_FRAMES)
	return sim.state.is_starving()


func _stage_hud() -> bool:
	sim.debug_set_ai_frozen(true)
	var spot := Vector2(-4.0, 16.0)
	if not sim.debug_teleport(spot, -PI / 2.0) or not sim.debug_set_energy(0.0):
		return false
	sim.debug_spawn_creature("rammer", spot + Vector2(3.0, 3.5), -2.2)
	await _play(_whole_frames(STARVE_FRAMES))
	return sim.state.is_starving()


## The cell in the middle of SUNLIT_ZONE, where its plankton grows, in the zone's sunlit patch.
func _stage_sunlit() -> bool:
	sim.debug_set_ai_frozen(true)
	var zone := _zone(SUNLIT_ZONE)
	if zone.is_empty() or not sim.debug_teleport(zone.center, -PI / 2.0):
		return false
	await _play(20)
	return true


## The cell sheltered (the sim's grace, as after a start) at SHELTER_SPOT, its rim faded in.
func _stage_shelter() -> bool:
	sim.debug_set_ai_frozen(true)
	if not sim.debug_teleport(SHELTER_SPOT, -PI / 2.0):
		return false
	sim.grace_until = sim.tick + 60 * Engine.physics_ticks_per_second
	await _play(SHELTER_FRAMES)
	return sim.is_sheltered()


## At least `frames`, and enough for a creature spawned now to finish fading in (the species
## data's fade_in_s; one frame is one sim tick at --fixed-fps 60), so it is drawn opaque and whole.
func _whole_frames(frames: int) -> int:
	return maxi(frames, sim.species.fade_in_ticks + 1)


# --- Endless scenes: staging --------------------------------------------------------------------

## The cell moved to `at_tm` (absolute tm) facing `heading`, the AI frozen, then START_FRAMES played
## there (at least long enough for a creature to fade in), so the view set round it is loaded and
## drawn. False in the pool.
func _stage_at(at_tm: Vector2, heading: float) -> bool:
	if sim.world == null:
		return false
	sim.debug_set_ai_frozen(true)
	var at := sim.world.abs_of_local(sim.world.local_of_tm(at_tm.x, at_tm.y))
	if not sim.debug_teleport_abs(at[0], at[1], heading):
		return false
	await _play(_whole_frames(START_FRAMES))
	return true


## The reef tile nearest the origin, framed on its densest knot of shells, facing north.
func _stage_reef() -> bool:
	if sim.world == null:
		return false
	var band := WorldConfig.band_of(sim.world.size)
	var tile_tm := _tile_tm()
	var best := Vector2i.MAX
	var best_d := INF
	for ty in range(-SEARCH_TILES, SEARCH_TILES + 1):
		for tx in range(-SEARCH_TILES, SEARCH_TILES + 1):
			if sim.world.gen.tile_info(band, tx, ty).region != "reef":
				continue
			var d := ((Vector2(tx, ty) + Vector2.ONE * 0.5) * tile_tm).length()
			if d < best_d:
				best = Vector2i(tx, ty)
				best_d = d
	if best == Vector2i.MAX:
		return false
	var shells: Array[Vector2] = []
	var per_tile := roundi(tile_tm / sim.world.chunk_tm)
	for cy in range(best.y * per_tile, (best.y + 1) * per_tile):
		for cx in range(best.x * per_tile, (best.x + 1) * per_tile):
			for e: Dictionary in sim.world.gen.chunk(sim.world.size, cx, cy).shells:
				if e.kind == "shell":
					shells.append(Vector2(float(e.x), float(e.y)))
	var knot: Array[Vector2] = []
	for a in shells:
		var near := shells.filter(func(b: Vector2) -> bool: return a.distance_to(b) <= REEF_KNOT_TM)
		if near.size() > knot.size():
			knot.assign(near)
	if knot.is_empty():
		return false
	var centroid := Vector2.ZERO
	for p in knot:
		centroid += p / knot.size()
	var at := centroid + Vector2(0.0, REEF_SOUTH_TM)
	_staged = {"tile": [best.x, best.y], "knot": knot.size(), "knot_centroid_tm": [snappedf(centroid.x, 0.01), snappedf(centroid.y, 0.01)],
		"at_tm": [snappedf(at.x, 0.01), snappedf(at.y, 0.01)]}
	return await _stage_at(at, -PI / 2.0)


## ANCHOR_SOUTH_TM south of the nearest landmark anchor, facing north: a shed husk when `shed`,
## otherwise any other landmark.
func _stage_anchor(shed: bool) -> bool:
	if sim.world == null:
		return false
	var a := _nearest(_sea().anchors.filter(func(x: Dictionary) -> bool: return (str(x.model) == SHED_HUSK) == shed))
	if a.is_empty():
		return false
	var at := Vector2(float(a.x), float(a.y) + ANCHOR_SOUTH_TM)
	_staged = {"id": str(a.id), "model": str(a.model), "dressing": str(a.dressing), "anchor_tm": [a.x, a.y], "at_tm": [at.x, at.y]}
	return await _stage_at(at, -PI / 2.0)


## The giant husk nearest the origin, side-on from the south (build plan B-30): the cell HUSK_GAP_TM
## south of its southmost collider, under the place's centre, facing north at the default zoom.
func _stage_husk() -> bool:
	if sim.world == null:
		return false
	var place := _nearest(_sea().places.filter(func(x: Dictionary) -> bool: return str(x.kind) == "giant_husk"))
	if place.is_empty():
		return false
	var prefix := "s_%s_r" % str(place.id).trim_prefix("p_")
	var south := -INF
	for c: Dictionary in _sea().set_pieces:
		if str(c.id).begins_with(prefix):
			south = maxf(south, float(c.y) + float(c.r))
	if not is_finite(south):
		return false
	var at := Vector2(float(place.x), south + HUSK_GAP_TM)
	_staged = {"id": str(place.id), "place_tm": [place.x, place.y], "yaw_deg": place.get("yaw_deg", 0.0),
		"mirror": place.get("mirror", false), "at_tm": [at.x, at.y]}
	return await _stage_at(at, -PI / 2.0)


## The tile's side in tm at the run's size.
func _tile_tm() -> float:
	return sim.world.content.config.tile_bu * WorldConfig.bu_to_tm(sim.world.size)


## The landmark anchors, rare places and set-piece colliders (WorldChunk, absolute tm) of every chunk
## within SEARCH_CHUNKS of the origin's, generated once: every scene starts the same sea.
func _sea() -> Dictionary:
	if not _sea_cache.is_empty():
		return _sea_cache
	var out := {"anchors": [], "places": [], "set_pieces": []}
	for cy in range(-SEARCH_CHUNKS, SEARCH_CHUNKS + 1):
		for cx in range(-SEARCH_CHUNKS, SEARCH_CHUNKS + 1):
			var ch: WorldChunk = sim.world.gen.chunk(sim.world.size, cx, cy)
			out.anchors.append_array(ch.anchors)
			out.places.append_array(ch.places)
			out.set_pieces.append_array(ch.shells.filter(func(x: Dictionary) -> bool: return x.kind == "set_piece"))
	_sea_cache = out
	return out


## The object nearest the origin (its x, y in tm; ties go to the smaller id), or {}.
static func _nearest(objects: Array) -> Dictionary:
	var best := {}
	var best_d := INF
	for o: Dictionary in objects:
		var d := Vector2(float(o.x), float(o.y)).length()
		if d < best_d or (d == best_d and str(o.id) < str(best.get("id", ""))):
			best = o
			best_d = d
	return best


# --- Scenes: frames and readings ----------------------------------------------------------------

## Captures the frozen moment's frames and takes its readings.
func _shoot(scene: String) -> void:
	match scene:
		"tell", "puff":
			await _shoot_lane(scene)
		"hud":
			await _shoot_hud(scene)
		"sunlit":
			await _shoot_sunlit(scene)
		"shelter":
			await _shoot_shelter(scene)
		"reef":
			await _shoot_reef(scene)
		"landmark", "husk", "shed_husk":
			await _shoot_piece(scene)
		"markers":
			await _shoot_markers(scene)
		"rebase_pair":
			await _shoot_rebase(scene)
		_:
			var frames := await _shoot_common(scene)
			var r: Dictionary = results[scene].readings
			if scene == "lineup":
				var panels := _hud_panels()
				r.plankton = _food_readings(frames[0], sim.plankton.items, pool.plankton_view.food_mesh(), panels)
				r.carrion = _food_readings(frames[0], sim.carrion.items, pool.carrion_view.food_mesh(), panels)
				var ambush: Array = r.creatures.filter(func(c: Dictionary) -> bool: return c.species == "ambush_hunter")
				if not ambush.is_empty():
					r.ambush_dL = ambush.map(func(c: Dictionary) -> float: return c.dL).min()
			elif scene == "rim_north":
				r.skirt = _skirt_readings(await _wall_frame(scene, frames[1]))
			_write_points(scene, frames[0])


## The vignette at its peak (Hud.VIGNETTE_PEAK) in the full frame; then the 3D frame with a copy of
## the vignette alone and with no 2D layer, for its outer band (the four corners) and what lies behind.
func _shoot_hud(scene: String) -> void:
	var vignette: ColorRect = main.hud.get("hurt_vignette")
	if vignette == null or not vignette.material is ShaderMaterial:
		results[scene].error = "the HUD has no hurt vignette to measure"
		return
	(vignette.material as ShaderMaterial).set_shader_parameter(&"strength", Hud.VIGNETTE_PEAK)
	vignette.visible = true
	var frames := await _shoot_common(scene)
	var layer := CanvasLayer.new()
	layer.layer = pool.ui.layer
	var copy := vignette.duplicate() as ColorRect
	layer.add_child(copy)
	copy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pool.add_child(layer)
	pool.ui.visible = false
	var alone := await _capture()
	layer.visible = false
	layer.queue_free()
	var world := await _capture()
	pool.ui.visible = true
	_save(scene, "vignette", alone)
	_save(scene, "world", world)
	var r: Dictionary = results[scene].readings
	var on := _corners_median(alone)
	var off := _corners_median(world)
	r.vignette = on
	r.vignette_behind = off
	r.vignette_dE = snappedf(delta_e(_color_of(on), _color_of(off)), 0.1)
	_write_points(scene, frames[0])


## The sunlit scene: its frames, then the fluid frame with the zone lights hidden, for the patch.
## Then an ambush hunter is let in where the patch is brightest, between the camera and that point,
## and shot against what lies behind it (<scene>_ambush.png): the worst a patch does to a body.
func _shoot_sunlit(scene: String) -> void:
	var frames := await _shoot_common(scene)
	_show_gameplay(false)
	pool.zone_lights.visible = false
	var dark := await _capture()
	pool.zone_lights.visible = true
	_show_gameplay(true)
	_save(scene, "nopatch", dark)
	var zone := _zone(SUNLIT_ZONE)
	var patch := _patch_readings(zone, frames[1], dark)
	results[scene].readings.patch = patch
	_write_points(scene, frames[0])
	var top: Dictionary = {}
	for p: Dictionary in patch.profile:
		if top.is_empty() or p.dL > top.dL:
			top = p
	if top.is_empty():
		return
	# Where the view ray to the brightest point crosses the swim plane.
	var lit := PlaneSpace.to_world(Vector2(zone.center) + Vector2.from_angle(deg_to_rad(top.deg)) * float(zone.radius) * top.at, ZoneLights.DEPTH_M)
	var eye := pool.camera.global_position
	var on_plane := lit + (eye - lit) * (-lit.y / (eye.y - lit.y))
	_thaw()
	pool.set_paused(false)
	var spawned := sim.debug_spawn_creature("ambush_hunter", Vector2(on_plane.x, on_plane.z), -PI / 2.0)
	await _play(_whole_frames(1))
	await _freeze()
	if not spawned:
		results[scene].readings.ambush = {"error": "no room for the hunter at %s" % Vector2(on_plane.x, on_plane.z)}
		return
	_boxes.clear()
	var full := await _capture(FIRST_SETTLE)
	_show_gameplay(false)
	var fluid := await _capture()
	_show_gameplay(true)
	_save(scene, "ambush", full)
	var hunters: Array = _creature_readings(full, fluid).filter(func(c: Dictionary) -> bool: return c.species == "ambush_hunter")
	if hunters.is_empty():
		results[scene].readings.ambush = {"error": "the hunter is not on screen"}
		return
	var nearest: Dictionary = hunters[0]
	var at := _px(on_plane)
	for h: Dictionary in hunters:
		if Vector2(h.px[0], h.px[1]).distance_to(at) < Vector2(nearest.px[0], nearest.px[1]).distance_to(at):
			nearest = h
	nearest.patch_point = top
	results[scene].readings.ambush = nearest


## The shelter scene: the cell's rim held at mid pulse (half way between its least and most alpha),
## then the same moment with the rim off, and the fluid frame with the zone lights hidden.
func _shoot_shelter(scene: String) -> void:
	var view := pool.cell_view
	if not view._sheltered:
		results[scene].error = "the cell view is not sheltered"
		return
	view._shelter = 1.0
	view._shelter_phase = PI / 2.0
	view._update_overlay(0.0)
	var frames := await _shoot_common(scene)
	var rim: Color = view.overlay_colors().rim
	view.set_sheltered(false)
	view._shelter = 0.0
	view._update_overlay(0.0)
	var bare := await _capture()
	_show_gameplay(false)
	pool.zone_lights.visible = false
	var unlit := await _capture()
	pool.zone_lights.visible = true
	_show_gameplay(true)
	_save(scene, "bare", bare)
	_save(scene, "unlit", unlit)
	var out := _rim_readings(frames[0], bare, frames[1], unlit)
	out.rim_alpha = snappedf(rim.a, 0.001)
	results[scene].readings.shelter = out
	_write_points(scene, frames[0])


## The shelter rim: per pixel of the cell's outer band (its own pixels, where the frame differs from
## the fluid frame, SHELTER_BAND of its radius out on screen), L* with the rim against without it;
## the band's median against the fluid just outside the cell (SHELTER_OUTSIDE); and the L* the
## zone lights add to the fluid behind the band.
## {"pixels", "rim_lift_mean_dL", "rim_lift_p90_dL", "rim", "rim_bare", "outside",
## "rim_vs_outside_dL", "behind_lift_dL"}.
func _rim_readings(on: Image, off: Image, fluid: Image, unlit: Image) -> Dictionary:
	var at := _px(pool.cell_view.global_position)
	var r := _px_radius(pool.cell_view.global_position, sim.phenotype.radius)
	var lifts := PackedFloat32Array()
	var band := PackedColorArray()
	var band_off := PackedColorArray()
	var outside := PackedColorArray()
	var behind_lit := PackedColorArray()
	var behind_unlit := PackedColorArray()
	var box := _disc_rect(at, r * SHELTER_OUTSIDE.y).intersection(Rect2i(Vector2i.ZERO, on.get_size()))
	_boxes.append(box)
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var d := Vector2(x, y).distance_to(at) / r
			var a := on.get_pixel(x, y)
			var b := off.get_pixel(x, y)
			var f := fluid.get_pixel(x, y)
			var body := maxf(absf(b.r - f.r), maxf(absf(b.g - f.g), absf(b.b - f.b))) > MARKER_CHANGE
			if body and d >= SHELTER_BAND.x and d <= SHELTER_BAND.y:
				lifts.append(lab(a).x - lab(b).x)
				band.append(a)
				band_off.append(b)
				behind_lit.append(f)
				behind_unlit.append(unlit.get_pixel(x, y))
			elif not body and d >= SHELTER_OUTSIDE.x and d <= SHELTER_OUTSIDE.y:
				outside.append(a)
	if lifts.is_empty():
		return {"error": "the cell is not on screen"}
	var mean := 0.0
	for l in lifts:
		mean += l / lifts.size()
	var sorted := lifts.duplicate()
	sorted.sort()
	var rim := median_color(band)
	var out := {
		"pixels": lifts.size(),
		"rim_lift_mean_dL": snappedf(mean, 0.1),
		"rim_lift_p90_dL": snappedf(sorted[int(sorted.size() * 0.9)], 0.1),
		"rim": reading(rim), "rim_bare": reading(median_color(band_off)), "outside": reading(median_color(outside)),
		"behind_lift_dL": snappedf(lab(median_color(behind_lit)).x - lab(median_color(behind_unlit)).x, 0.1),
	}
	out.rim_vs_outside_dL = snappedf(absf(out.rim.L - out.outside.L), 0.1)
	return out


## A tell scene: the frames with and without the lane, over the fluid and over the decor stand-in.
func _shoot_lane(scene: String) -> void:
	var tell := _last_tell()
	var view: CreatureView = pool.creature_layer.view_of(str(tell.get("id", "")))
	if view == null or not view.lane_visible():
		results[scene].error = "the telling creature shows no lane"
		return
	var frames := await _shoot_common(scene)
	var lane: Dictionary = tell.lane
	view.hide_lane()
	var bare := await _capture()
	pool.zone_lights.visible = false
	var unlit := await _capture()
	pool.zone_lights.visible = true
	view.show_lane(lane)
	_add_decor(lane)
	var decor := await _capture()
	view.hide_lane()
	var decor_bare := await _capture()
	view.show_lane(lane)
	_save(scene, "nolane", bare)
	_save(scene, "decor", decor)
	_save(scene, "decor_nolane", decor_bare)
	results[scene].readings.lane = _lane_readings(lane, frames[0], bare, decor, decor_bare)
	results[scene].readings.lane.merge(_lane_patch(lane, bare, unlit))
	results[scene].readings.marker = await _marker_readings(scene, view)
	_write_points(scene, frames[0])


# --- Endless scenes: frames and readings -------------------------------------------------------

## The reef: its frames, then the same moment with every shell hidden, for the shells' own pixels.
func _shoot_reef(scene: String) -> void:
	var frames := await _shoot_common(scene)
	pool.rocks.visible = false
	var bare := await _capture()
	pool.rocks.visible = true
	_save(scene, "norocks", bare)
	results[scene].readings.shells = _shell_readings(frames[0], frames[1], bare)
	_write_points(scene, frames[0])


## Each shell on screen and clear of HUD panels, nearest the screen centre first: its silhouette,
## the pixels it draws in its projected box (its mesh's box at its instance), against the fluid frame
## there. The shells are drums and towers 2.4 to 2.7 m tall, with lit tops and fluid-tinted sides,
## so the whole silhouette is read, not a disc at the projected centre (the content doc's core), which
## falls on the top or the side by where the shell stands on screen. A shell with less than
## SHELL_ON_SCREEN of its box on screen is left out. {"items", "count", "achromatic", "food_gap_min", "threat_gap_min", "fluid_dL_min",
## "fluid_dL_px_min", "fluid_dL_px_median"}; no minimum when no shell could be read.
func _shell_readings(full: Image, fluid: Image, bare: Image) -> Dictionary:
	var panels := _hud_panels()
	var screen := Rect2i(Vector2i.ZERO, full.get_size())
	var centre := Vector2(full.get_size()) * 0.5
	var found := []
	for asset in pool.rocks.assets_in_use():
		var piece: Dictionary = pool.rocks._pieces[asset]
		var mesh_box: AABB = (piece.mesh as Mesh).get_aabb()
		for e: Dictionary in pool.rocks.instances_of(asset):
			var t: Transform3D = pool.rocks.global_transform * e.transform * piece.offset
			var w := t * mesh_box.get_center()
			if not _on_screen(w, full):
				continue
			var whole := _project_box(t * mesh_box)
			var box := whole.intersection(screen)
			if box.get_area() < SHELL_ON_SCREEN * whole.get_area() or panels.any(func(p: Rect2) -> bool: return p.intersects(Rect2(box))):
				continue
			var drawn := _drawn(full, bare, fluid, box)
			if drawn.on.size() < SHELL_PIXELS_NEEDED:
				continue
			_boxes.append(box)
			var at := _px(w)
			var one := _against_fluid(drawn)
			one.merge({"id": e.id, "asset": asset, "px": [roundi(at.x), roundi(at.y)], "d": snappedf(at.distance_to(centre), 0.1)})
			found.append(one)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	var out := {"items": found, "count": found.size(), "achromatic": found.filter(func(x: Dictionary) -> bool: return x.achromatic).size()}
	if found.is_empty():
		return out
	out.food_gap_min = found.map(func(x: Dictionary) -> float: return x.food_gap).min()
	out.threat_gap_min = found.map(func(x: Dictionary) -> float: return x.threat_gap).min()
	out.fluid_dL_min = found.map(func(x: Dictionary) -> float: return x.fluid_dL).min()
	var each: Array = found.map(func(x: Dictionary) -> float: return x.fluid_dL_px)
	out.fluid_dL_px_min = each.min()
	each.sort()
	out.fluid_dL_px_median = each[each.size() / 2]
	return out


## A landmark or the husk (the staged piece): its frames, then the same moment with that piece
## hidden, for its silhouette in its projected box against the fluid frame.
func _shoot_piece(scene: String) -> void:
	var piece := _piece_node(str(_staged.get("id", "")))
	if piece == null:
		results[scene].error = "%s is not drawn" % _staged.get("id", "the piece")
		return
	var frames := await _shoot_common(scene)
	piece.visible = false
	var without := await _capture()
	piece.visible = true
	_save(scene, "nopiece", without)
	var box := _screen_box(piece)
	_boxes.append(box)
	results[scene].readings.merge(_against_fluid(_drawn(frames[0], without, frames[1], box)))
	results[scene].readings.box = [box.position.x, box.position.y, box.size.x, box.size.y]
	_write_points(scene, frames[0])


## The arrow home and the column's pip: the frames, then the moment with both markers hidden and
## with the HUD's world overlay hidden.
func _shoot_markers(scene: String) -> void:
	var arrow := pool.markers.arrow()
	var overlay: Control = main.hud.world_overlay
	if arrow == null or not arrow.visible or overlay == null:
		results[scene].error = "the arrow home is not showing"
		return
	var frames := await _shoot_common(scene)
	pool.markers.visible = false
	var bare := await _capture()
	pool.markers.visible = true
	overlay.visible = false
	var plain := await _capture()
	overlay.visible = true
	_save(scene, "nomarkers", bare)
	_save(scene, "nooverlay", plain)
	var r: Dictionary = results[scene].readings
	var mesh := arrow.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var core := _disc_point(frames[0], _px(mesh.global_transform * mesh.get_aabb().get_center()), ARROW_DISC_PX)
	r.arrow_centre = core
	r.arrow_L = core.L
	var box := _screen_box(arrow)
	_boxes.append(box)
	r.arrow = _against_fluid(_drawn(frames[0], bare, frames[1], box))
	var state: Dictionary = pool.markers.arrow_state()
	r.arrow_state = {"distance_tm": snappedf(float(state.distance_tm), 0.1),
		"direction": [snappedf(state.direction.x, 0.001), snappedf(state.direction.y, 0.001)]}
	r.pip_present = 0
	r.pip = {}
	var pip: Dictionary = overlay.get("pip")
	if pip.has("at"):
		var at: Vector2 = pip.at
		var pip_box := _disc_rect(at, Hud.WorldOverlay.PIP_RADIUS_PX + Hud.WorldOverlay.PIP_OUTLINE_PX + 2.0)
		_boxes.append(pip_box)
		var drawn := _drawn(frames[0], plain, frames[1], pip_box)
		r.pip = {"at": [roundi(at.x), roundi(at.y)], "pixels": drawn.on.size()}
		if not drawn.on.is_empty():
			r.pip.color = reading(median_color(drawn.on))
			r.pip_present = 1
	_write_points(scene, frames[0])


## The rebase pair (G10): frame A of the paused moment, A again with nothing changed, then a dev
## rebase by REBASE_BY chunks routed as the pool routes it and frame B. A rebase never shows when B
## matches A about as well as A matches itself.
func _shoot_rebase(scene: String) -> void:
	_boxes.clear()
	var a := await _capture(FIRST_SETTLE)
	var still := await _capture()
	var before := [sim.world.origin_x_am, sim.world.origin_y_am]
	if not sim.debug_rebase(REBASE_BY):
		results[scene].error = "the dev rebase did not run"
		return
	var b := await _capture()
	_save(scene, "", a)
	_save(scene, "still", still)
	_save(scene, "after", b)
	var whole := Rect2i(Vector2i.ZERO, a.get_size())
	var moved := delta_e_spread(a, b, whole, PARITY_STRIDE)
	var same := delta_e_spread(a, still, whole, PARITY_STRIDE)
	var r: Dictionary = results[scene].readings
	r.render_info = _render_info()
	r.origin_moved_am = [sim.world.origin_x_am - before[0], sim.world.origin_y_am - before[1]]
	if not moved.is_empty():
		r.median_dE = moved.median
		r.p99_dE = moved.p99
		r.max_dE = moved.max
	if not same.is_empty():
		r.still_median_dE = same.median
		r.still_p99_dE = same.p99


## The pixels a piece draws in `rect` (within `radius` of `center` when one is given): where `full`
## differs from `without` (the moment without it) by more than SILHOUETTE_CHANGE in a channel, with
## the fluid frame's pixels there. {"on", "behind" (PackedColorArray), "of" (pixels looked at)}.
func _drawn(full: Image, without: Image, fluid: Image, rect: Rect2i, center := Vector2.INF, radius := 0.0) -> Dictionary:
	var area := rect.intersection(Rect2i(Vector2i.ZERO, full.get_size()))
	var on := PackedColorArray()
	var behind := PackedColorArray()
	var of := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if radius > 0.0 and Vector2(x, y).distance_to(center) > radius:
				continue
			of += 1
			var a := full.get_pixel(x, y)
			var b := without.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > SILHOUETTE_CHANGE:
				on.append(a)
				behind.append(fluid.get_pixel(x, y))
	return {"on": on, "behind": behind, "of": of}


## A piece's drawn pixels (_drawn) against the fluid behind them: their medians, how many and what
## share of the pixels looked at, |dL*| between the medians (fluid_dL), the median of each pixel's
## own |dL*| (fluid_dL_px: texture and shading count there), and the LAB hue gaps from the food and
## threat colours (180 for a colour under ACHROMATIC_C chroma). {"silhouette", "silhouette_behind",
## "pixels", "share", "fluid_dL", "fluid_dL_px", "achromatic", "food_gap", "threat_gap"}.
func _against_fluid(drawn: Dictionary) -> Dictionary:
	var on: PackedColorArray = drawn.on
	var piece := reading(median_color(on))
	var behind := reading(median_color(drawn.behind))
	var out := {"silhouette": piece, "silhouette_behind": behind, "pixels": on.size(),
		"share": snappedf(on.size() / float(maxi(int(drawn.of), 1)), 0.01)}
	if on.is_empty():
		return out
	out.fluid_dL = _dl(piece, behind)
	var each := PackedFloat32Array()
	for i in on.size():
		each.append(absf(lab(on[i]).x - lab(drawn.behind[i]).x))
	each.sort()
	out.fluid_dL_px = snappedf(each[each.size() / 2], 0.1)
	out.achromatic = piece.C < ACHROMATIC_C
	out.food_gap = 180.0 if out.achromatic else snappedf(hue_gap(piece.h, hue(lab(Color(FOOD_HEX)))), 0.1)
	out.threat_gap = 180.0 if out.achromatic else snappedf(hue_gap(piece.h, hue(lab(Color(THREAT_HEX)))), 0.1)
	return out


## The landmark layer's piece named `id` (an anchor's or a rare place's), or null.
func _piece_node(id: String) -> Node3D:
	for piece in pool.landmarks.pieces():
		if str(piece.name) == id:
			return piece
	return null


## The screen box round the bounding boxes of a node's visible meshes, clipped to the screen.
func _screen_box(node: Node3D) -> Rect2i:
	var box := Rect2i()
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.is_visible_in_tree():
			var one := _project_box(mi.global_transform * mi.get_aabb())
			box = box.merge(one) if box.has_area() else one
	return box.intersection(Rect2i(Vector2i.ZERO, root.size))


## The screen box round a world box's eight corners (unclipped).
func _project_box(aabb: AABB) -> Rect2i:
	var box := Rect2(_px(aabb.get_endpoint(0)), Vector2.ZERO)
	for k in range(1, 8):
		box = box.expand(_px(aabb.get_endpoint(k)))
	return Rect2i(Vector2i(box.position.floor()), Vector2i(box.end.ceil()) - Vector2i(box.position.floor()))


# --- Measuring -----------------------------------------------------------------------------------

## cell, cell_behind, fluid_near_cell, cell_dL, fluid_threat_hue_gap, the fluid bands and corners,
## and glow_dL.
func _common_readings(full: Image, fluid: Image) -> Dictionary:
	var w := full.get_width()
	var h := full.get_height()
	var at := _px(pool.cell_view.global_position)
	var core := CELL_CORE * _px_radius(pool.cell_view.global_position, sim.phenotype.radius)
	var out := {}
	out.cell = _disc_point(full, at, core)
	out.cell_behind = _disc_point(fluid, at, core)
	out.fluid_near_cell = _box_point(fluid, Rect2i(w / 3, h / 3, w / 3, h / 3), 2)
	out.cell_dL = _dl(out.cell, out.fluid_near_cell)
	out.fluid_threat_hue_gap = snappedf(hue_gap(out.fluid_near_cell.h, hue(lab(Color(THREAT_HEX)))), 0.1)
	out.fluid_top = _box_point(fluid, Rect2i(int(w * 0.3125), 0, int(w * 0.4167), int(h * 0.111)), 2)
	out.fluid_bottom = _box_point(fluid, Rect2i(int(w * 0.3125), int(h * 0.889), int(w * 0.4167), int(h * 0.111)), 2)
	var cw := int(w * 0.078)
	var ch := int(h * 0.111)
	var corner_l: Array[float] = []
	for corner: Array in [["tl", 0, 0], ["tr", w - cw, 0], ["bl", 0, h - ch], ["br", w - cw, h - ch]]:
		var p := _box_point(fluid, Rect2i(corner[1], corner[2], cw, ch), 2)
		out["fluid_corner_" + corner[0]] = p
		corner_l.append(p.L)
	var mean_l := 0.0
	for l in corner_l:
		mean_l += l / corner_l.size()
	out.fluid_corners_min_L = corner_l.min()
	out.glow_dL = snappedf(out.fluid_near_cell.L - mean_l, 0.1)
	return out


## Each creature on screen: its body's core against the fluid behind it.
func _creature_readings(full: Image, fluid: Image) -> Array:
	var out := []
	if sim.creatures == null:
		return out
	for c in sim.creatures.creatures:
		var view := pool.creature_layer.view_of(c.id)
		if view == null or not _on_screen(view.global_position, full):
			continue
		var at := _px(view.global_position)
		var core := BODY_CORE * _px_radius(view.global_position, view.radius)
		var body := _disc_point(full, at, core)
		var behind := _disc_point(fluid, at, core)
		body.merge({"id": c.id, "species": c.species_id, "dL": _dl(body, behind),
			"dE": snappedf(delta_e(_color_of(body), _color_of(behind)), 0.1), "behind_L": behind.L,
			"px": [roundi(at.x), roundi(at.y)]})
		out.append(body)
	return out


## Food items on screen and clear of bodies and HUD panels, nearest the screen centre first: each
## one's core, the hue span, the highest channel over their whole discs and the hue gap from the
## threat colour. {"items", "count", "h_min", "h_max", "max_channel", "threat_hue_gap"}.
func _food_readings(full: Image, items: Array[Dictionary], mesh: Mesh, panels: Array[Rect2]) -> Dictionary:
	var size := mesh.get_aabb().size if mesh != null else Vector3.ONE * 0.4
	var radius_m := maxf(size.x, size.z) * 0.5
	var centre := Vector2(full.get_size()) * 0.5
	var found := []
	for item in items:
		var w := PlaneSpace.to_world(item.position)
		if not _on_screen(w, full):
			continue
		var at := _px(w)
		var r := _px_radius(w, radius_m)
		if _covered(at, r) or panels.any(func(p: Rect2) -> bool: return p.grow(r).has_point(at)):
			continue
		found.append({"at": at, "r": r, "d": at.distance_to(centre)})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	var out := {"items": [], "count": 0}
	var hues: Array[float] = []
	var top := 0
	var threat_h := hue(lab(Color(THREAT_HEX)))
	var gap := 360.0
	for f: Dictionary in found.slice(0, MAX_FOOD_ITEMS):
		var p := _disc_point(full, f.at, FOOD_CORE * f.r)
		var whole := median_of(full, _disc_rect(f.at, f.r), 1, f.at, f.r)
		p.max_channel = whole.max_channel
		out.items.append(p)
		hues.append(p.h)
		top = maxi(top, whole.max_channel)
		gap = minf(gap, hue_gap(p.h, threat_h))
	out.count = hues.size()
	if hues.is_empty():
		return out
	out.h_min = hues.min()
	out.h_max = hues.max()
	out.max_channel = top
	out.threat_hue_gap = snappedf(gap, 0.1)
	return out


## The lane's outline against the same pixels without it, over the fluid and over the decor
## stand-in: at each LANE_FRACTIONS place on both sides, the largest |dL*| across the edge. Places
## a body covers are left out; with fewer than LANE_POINTS_NEEDED left the minimum is not given.
func _lane_readings(lane: Dictionary, on: Image, off: Image, decor_on: Image, decor_off: Image) -> Dictionary:
	var heading := float(lane.heading)
	var dir := Vector2.from_angle(heading)
	var across := dir.orthogonal()
	var half := float(lane.half_width)
	var out := {"half_width_m": half, "length_m": float(lane.length), "over_fluid": [], "over_decor": []}
	for f in LANE_FRACTIONS:
		var mid: Vector2 = Vector2(lane.origin) + dir * float(lane.length) * f
		for side in [-1.0, 1.0]:
			var scan := PackedVector2Array()
			var covered := false
			for k in LANE_SCAN_STEPS:
				var d := lerpf(half - LANE_SCAN_IN_M, half + LANE_SCAN_OUT_M, k / float(LANE_SCAN_STEPS - 1))
				var px := _px(PlaneSpace.to_world(mid + across * side * d, CreatureView.LANE_Y))
				covered = covered or _covered(px, 0.0) or not Rect2(Vector2.ZERO, Vector2(on.get_size())).has_point(px)
				scan.append(px)
			for pair: Array in [["over_fluid", on, off], ["over_decor", decor_on, decor_off]]:
				var best := {"at": f, "side": side, "covered": covered, "dL": 0.0, "dE": 0.0}
				if not covered:
					for px in scan:
						var a := _color_of(median_of(pair[1], _disc_rect(px, 1.0)))
						var b := _color_of(median_of(pair[2], _disc_rect(px, 1.0)))
						var dl := absf(lab(a).x - lab(b).x)
						if dl > best.dL:
							best.dL = snappedf(dl, 0.1)
							best.dE = snappedf(delta_e(a, b), 0.1)
							best.px = [roundi(px.x), roundi(px.y)]
					_boxes.append(Rect2i(Vector2i(scan[0]), Vector2i.ONE).expand(Vector2i(scan[scan.size() - 1])).grow(2))
				out[pair[0]].append(best)
	for key in ["over_fluid", "over_decor"]:
		var measured: Array = out[key].filter(func(p: Dictionary) -> bool: return not p.covered)
		out[key + "_points"] = measured.size()
		if measured.size() >= LANE_POINTS_NEEDED:
			out[key + "_min_dL"] = measured.map(func(p: Dictionary) -> float: return p.dL).min()
	return out


## How much the sunlit patches light the fluid under the lane's edge: the L* the zone lights add
## (`lit` against `unlit`, both without the lane) at LANE_FRACTIONS of its length on both sides.
## {"patch_lift_max_dL", "patch_lift_mean_dL"}: a lane over a patch shows a lift here.
func _lane_patch(lane: Dictionary, lit: Image, unlit: Image) -> Dictionary:
	var dir := Vector2.from_angle(float(lane.heading))
	var lifts: Array[float] = []
	for f in LANE_FRACTIONS:
		for side in [-1.0, 1.0]:
			var at: Vector2 = Vector2(lane.origin) + dir * float(lane.length) * f + dir.orthogonal() * side * float(lane.half_width)
			var px := _px(PlaneSpace.to_world(at, CreatureView.LANE_Y))
			if _covered(px, 0.0) or not Rect2(Vector2.ZERO, Vector2(lit.get_size())).has_point(px):
				continue
			var rect := _disc_rect(px, PATCH_BOX_PX * 0.5)
			lifts.append(lab(_color_of(median_of(lit, rect))).x - lab(_color_of(median_of(unlit, rect))).x)
	if lifts.is_empty():
		return {}
	var mean := 0.0
	for l in lifts:
		mean += l / lifts.size()
	return {"patch_lift_max_dL": snappedf(lifts.max(), 0.1), "patch_lift_mean_dL": snappedf(mean, 0.1)}


## The "!" over the telling creature, popped to full size, against the same moment without it
## (saved as <scene>_marker.png), over the fluid (the decor stand-in hidden): each pixel it changes
## counts as outline or glyph, whichever of the two colours it is nearer, and the frame without it
## gives what lies behind those pixels.
## {"outline", "glyph", "behind" (points), "outline_px", "glyph_px", "outline_contrast",
## "glyph_contrast", "outline_glyph_contrast" (WCAG contrast ratios)}.
func _marker_readings(scene: String, view: CreatureView) -> Dictionary:
	var marker := view.get_node("%Marker") as Label3D
	if _decor != null:
		_decor.visible = false
	view.show_marker()
	view._process(CreatureView.MARKER_POP_S)
	if not marker.visible:
		return {"error": "the marker does not show"}
	var on := await _capture()
	marker.visible = false
	var off := await _capture()
	_save(scene, "marker", on)
	var at := Vector2i(_px(marker.global_position))
	var box := Rect2i(at - Vector2i.ONE * MARKER_BOX_PX, Vector2i.ONE * MARKER_BOX_PX * 2).intersection(Rect2i(Vector2i.ZERO, on.get_size()))
	_boxes.append(box)
	var outline := PackedColorArray()
	var glyph := PackedColorArray()
	var behind := PackedColorArray()
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var a := on.get_pixel(x, y)
			var b := off.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) <= MARKER_CHANGE:
				continue
			var to_outline := Vector3(a.r, a.g, a.b).distance_to(Vector3(CreatureView.MARKER_OUTLINE.r, CreatureView.MARKER_OUTLINE.g, CreatureView.MARKER_OUTLINE.b))
			var to_glyph := Vector3(a.r, a.g, a.b).distance_to(Vector3(CreatureView.MARKER_COLOR.r, CreatureView.MARKER_COLOR.g, CreatureView.MARKER_COLOR.b))
			(outline if to_outline < to_glyph else glyph).append(a)
			behind.append(b)
	if outline.is_empty() or glyph.is_empty():
		return {"error": "no marker pixels", "outline_px": outline.size(), "glyph_px": glyph.size()}
	var out := {"outline": reading(median_color(outline)), "glyph": reading(median_color(glyph)), "behind": reading(median_color(behind)),
		"outline_px": outline.size(), "glyph_px": glyph.size()}
	out.outline_contrast = snappedf(contrast(median_color(outline), median_color(behind)), 0.01)
	out.glyph_contrast = snappedf(contrast(median_color(glyph), median_color(behind)), 0.01)
	out.outline_glyph_contrast = snappedf(contrast(median_color(outline), median_color(glyph)), 0.01)
	return out


## A zone's sunlit patch: the L* the zone lights add to the fluid frame (`lit` against `dark`) at
## PATCH_FRACTIONS of the zone's radius out from its centre, along PATCH_DIRECTIONS directions on the
## patches' plane (ZoneLights.DEPTH_M). {"profile": [{"at", "deg", "dL"}], "by_fraction": [{"at",
## "points", "mean_dL", "min_dL", "max_dL"}], "lift_max_dL", "lift_centre_dL", "ring_min_share"}.
## ring_min_share is the least lift over the most at the brightest radius: a plain ring of light, which
## reads as a target, lifts that radius evenly all round (1); light broken into shafts gives near 0.
func _patch_readings(zone: Dictionary, lit: Image, dark: Image) -> Dictionary:
	var out := {"zone": zone.get("id", ""), "profile": [], "by_fraction": []}
	if zone.is_empty():
		return out
	var bounds := Rect2(Vector2.ZERO, Vector2(lit.get_size()))
	var top := -INF
	var top_at := NAN
	for f in PATCH_FRACTIONS:
		var lifts: Array[float] = []
		for k in (1 if f == 0.0 else PATCH_DIRECTIONS):
			var deg := 360.0 * k / PATCH_DIRECTIONS
			var at: Vector2 = Vector2(zone.center) + Vector2.from_angle(deg_to_rad(deg)) * float(zone.radius) * f
			var px := _px(PlaneSpace.to_world(at, ZoneLights.DEPTH_M))
			if not bounds.grow(-PATCH_BOX_PX).has_point(px):
				continue
			var rect := _disc_rect(px, PATCH_BOX_PX * 0.5)
			_boxes.append(rect)
			var dl := lab(_color_of(median_of(lit, rect))).x - lab(_color_of(median_of(dark, rect))).x
			lifts.append(snappedf(dl, 0.1))
			out.profile.append({"at": f, "deg": deg, "dL": snappedf(dl, 0.1)})
			if dl > top:
				top = dl
				top_at = f
		if f == 0.0 and not lifts.is_empty():
			out.lift_centre_dL = lifts[0]
		if not lifts.is_empty():
			var mean := 0.0
			for l in lifts:
				mean += l / lifts.size()
			out.by_fraction.append({"at": f, "points": lifts.size(), "mean_dL": snappedf(mean, 0.1), "min_dL": lifts.min(), "max_dL": lifts.max()})
	if is_finite(top):
		out.lift_max_dL = snappedf(top, 0.1)
		for b: Dictionary in out.by_fraction:
			if b.at == top_at and b.points > 1:
				out.ring_min_share = snappedf(b.min_dL / maxf(b.max_dL, 1e-3), 0.01)
	return out


## The fluid frame for the skirt: with art's decor (the pool's "Ambience", when mounted) hidden too,
## saved as <scene>_wall.png, since an item drifting in front of the wall is not an edge on it (art
## PR #10 put a backdrop organism across the column: one step of 6.5). Without decor it is `fluid`.
func _wall_frame(scene: String, fluid: Image) -> Image:
	var ambience := pool.get_node_or_null(^"Ambience") as Node3D
	if ambience == null or not ambience.visible:
		return fluid
	_show_gameplay(false)
	ambience.visible = false
	var wall := await _capture()
	ambience.visible = true
	_show_gameplay(true)
	_save(scene, "wall", wall)
	return wall


## L* down the north wall below the cell, from SKIRT_TOP_Y to SKIRT_BOTTOM_Y, in the wall frame:
## a hard lower edge on the rim's skirt shows as a step between neighbouring samples.
func _skirt_readings(fluid: Image) -> Dictionary:
	var x := pool.cell_view.global_position.x
	var z := -sqrt(RIM_WALL_M * RIM_WALL_M - x * x)
	var profile := []
	var step := 0.0
	var last := NAN
	var y := SKIRT_TOP_Y
	while y >= SKIRT_BOTTOM_Y - 1e-6:
		var px := _px(Vector3(x, y, z))
		if Rect2(Vector2.ZERO, Vector2(fluid.get_size())).has_point(px):
			var l := lab(_color_of(median_of(fluid, _disc_rect(px, SKIRT_BOX_PX * 0.5)))).x
			profile.append({"y": y, "L": snappedf(l, 0.1)})
			if not is_nan(last):
				step = maxf(step, absf(l - last))
			last = l
			_boxes.append(_disc_rect(px, SKIRT_BOX_PX * 0.5))
		y -= SKIRT_STEP_M
	return {"profile": profile, "max_step_dL": snappedf(step, 0.1)}


## The median CIE76 between this run and the --parity run of the scene: over the whole frame, the
## fluid frame and the cell. Missing when the other run has no such frames or another size.
func _parity_readings(scene: String, full: Image, fluid: Image) -> Dictionary:
	var paths := [parity_dir.path_join(scene + ".png"), parity_dir.path_join(scene + "_fluid.png")]
	if not paths.all(func(p: String) -> bool: return FileAccess.file_exists(p)):
		return {"error": "no %s frames in %s" % [scene, parity_dir]}
	var other := Image.load_from_file(paths[0])
	var other_fluid := Image.load_from_file(paths[1])
	if other == null or other_fluid == null or other.get_size() != full.get_size():
		return {"error": "no %s frames of the same size in %s" % [scene, parity_dir]}
	other.convert(Image.FORMAT_RGB8)
	other_fluid.convert(Image.FORMAT_RGB8)
	var whole := Rect2i(Vector2i.ZERO, full.get_size())
	var at := _px(pool.cell_view.global_position)
	var core := CELL_CORE * _px_radius(pool.cell_view.global_position, sim.phenotype.radius)
	var out := {
		"frame_dE": median_delta_e(full, other, whole, PARITY_STRIDE),
		"fluid_dE": median_delta_e(fluid, other_fluid, whole, PARITY_STRIDE),
		"cell_dE": median_delta_e(full, other, _disc_rect(at, core), 1, at, core),
	}
	for key: String in out.keys():
		if is_nan(out[key]):
			out.erase(key)
	return out


## The four corner boxes of a frame as one point.
func _corners_median(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var cw := int(w * 0.078)
	var ch := int(h * 0.111)
	var pixels := Image.create(cw * 2, ch * 2, false, Image.FORMAT_RGB8)
	for corner: Array in [[0, 0, 0, 0], [w - cw, 0, cw, 0], [0, h - ch, 0, ch], [w - cw, h - ch, cw, ch]]:
		pixels.blit_rect(img, Rect2i(corner[0], corner[1], cw, ch), Vector2i(corner[2], corner[3]))
		_boxes.append(Rect2i(corner[0], corner[1], cw, ch))
	var m := median_of(pixels, Rect2i(Vector2i.ZERO, pixels.get_size()), 2)
	var p := reading(m.color)
	p.max_channel = m.max_channel
	return p


func _render_info() -> Dictionary:
	var out := {}
	for kind: Array in [["visible", Viewport.RENDER_INFO_TYPE_VISIBLE], ["shadow", Viewport.RENDER_INFO_TYPE_SHADOW]]:
		out[kind[0]] = {
			"objects": root.get_render_info(kind[1], Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
			"primitives": root.get_render_info(kind[1], Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
			"draw_calls": root.get_render_info(kind[1], Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		}
	return out


func _box_point(img: Image, rect: Rect2i, stride := 1) -> Dictionary:
	_boxes.append(rect)
	var m := median_of(img, rect, stride)
	var p := reading(m.color)
	p.max_channel = m.max_channel
	return p


func _disc_point(img: Image, at: Vector2, radius: float) -> Dictionary:
	var rect := _disc_rect(at, radius)
	_boxes.append(rect)
	var m := median_of(img, rect, 1, at, maxf(radius, 0.5))
	var p := reading(m.color)
	p.max_channel = m.max_channel
	return p


func _px(world: Vector3) -> Vector2:
	return pool.camera.unproject_position(world)


## A world radius at `world` in screen pixels.
func _px_radius(world: Vector3, radius: float) -> float:
	return _px(world + pool.camera.global_basis.x * radius).distance_to(_px(world))


func _on_screen(world: Vector3, img: Image) -> bool:
	return not pool.camera.is_position_behind(world) and Rect2(Vector2.ZERO, Vector2(img.get_size())).grow(-20.0).has_point(_px(world))


## Whether a body (the cell or a creature, COVER_MARGIN of its radius) covers a disc on screen.
func _covered(at: Vector2, radius: float) -> bool:
	var cell := pool.cell_view.global_position
	if at.distance_to(_px(cell)) < COVER_MARGIN * _px_radius(cell, sim.phenotype.radius) + radius:
		return true
	for view in pool.creature_layer.views():
		if at.distance_to(_px(view.global_position)) < COVER_MARGIN * _px_radius(view.global_position, view.radius) + radius:
			return true
	return false


## Screen rects of the HUD's panels that are showing.
func _hud_panels() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for node in main.hud.find_children("*", "PanelContainer", true, false):
		if (node as Control).is_visible_in_tree():
			out.append((node as Control).get_global_rect())
	return out


## The pale decor stand-in, camera-facing, on the view ray through the lane's middle at DECOR_Y.
func _add_decor(lane: Dictionary) -> void:
	var mid: Vector2 = Vector2(lane.origin) + Vector2.from_angle(float(lane.heading)) * float(lane.length) * 0.5
	var eye := pool.camera.global_position
	var ray := (PlaneSpace.to_world(mid, CreatureView.LANE_Y) - eye).normalized()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(DECOR_COLOR, DECOR_ALPHA)
	mat.render_priority = -5
	var quad := QuadMesh.new()
	var reach := (DECOR_Y - eye.y) / ray.y
	quad.size = Vector2.ONE * float(lane.length) * 2.5 * reach / eye.distance_to(PlaneSpace.to_world(mid))
	_decor = MeshInstance3D.new()
	_decor.name = "ProbeDecor"
	_decor.mesh = quad
	_decor.material_override = mat
	_decor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.add_child(_decor)
	_decor.global_position = eye + ray * reach
	_decor.global_basis = pool.camera.global_basis


## The layout's zone `id`, or {}.
func _zone(id: String) -> Dictionary:
	for zone in sim.layout.zones:
		if zone.id == id:
			return zone
	return {}


func _creature_at(site_id: String) -> CreatureField.Creature:
	for c in sim.creatures.creatures:
		if c.site_id == site_id:
			return c
	return null


## The last tell on the cell this run, or {}.
func _last_tell() -> Dictionary:
	for i in range(events.size() - 1, -1, -1):
		if events[i].type == "creature_tell" and events[i].get("target") == CreatureField.PLAYER_ID:
			return events[i]
	return {}


func _write_points(scene: String, full: Image) -> void:
	var img := full.duplicate() as Image
	var bounds := Rect2i(Vector2i.ZERO, img.get_size())
	for box in _boxes:
		var b := box.grow(1).intersection(bounds)
		for edge in [Rect2i(b.position, Vector2i(b.size.x, 1)), Rect2i(b.position + Vector2i(0, b.size.y - 1), Vector2i(b.size.x, 1)),
				Rect2i(b.position, Vector2i(1, b.size.y)), Rect2i(b.position + Vector2i(b.size.x - 1, 0), Vector2i(1, b.size.y))]:
			img.fill_rect(edge, BOX_COLOR)
	_save(scene, "points", img)


## The readings of every scene that ran; one that could not be staged has none, so its gates fail.
func _readings() -> Dictionary:
	var out := {}
	for scene: String in results:
		out[scene] = results[scene].readings
	return out


func _write_report(gates: Array[Dictionary], failed: int) -> void:
	var window := root.size
	var report := {
		"probe": "tools/godot/look_probe.gd",
		"look": look,
		"build": BuildInfo.build_id(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"resolution": [window.x, window.y],
		"body": BODY,
		"seed": SEED,
		"world": world,
		"zoom": pool.camera.distance if pool != null else zoom,
		"parity_with": parity_dir,
		"gates": gates,
		"failed": failed,
		"scenes": results,
	}
	var file := FileAccess.open(out_dir.path_join("look_probe.json"), FileAccess.WRITE)
	if file == null:
		printerr("Look probe could not write its report: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(report, "\t", false))
	file.close()


func _dl(a: Dictionary, b: Dictionary) -> float:
	return snappedf(absf(float(a.L) - float(b.L)), 0.1)


static func _color_of(p: Dictionary) -> Color:
	return p.color if p.has("color") else Color(str(p.hex))


static func _disc_rect(at: Vector2, radius: float) -> Rect2i:
	var r := ceili(radius)
	return Rect2i(Vector2i(roundi(at.x) - r, roundi(at.y) - r), Vector2i(2 * r + 1, 2 * r + 1))


# --- Colour and gates (pure; tests/test_look_probe.gd checks them) -------------------------------

## CIELAB (D65) of an sRGB colour: Vector3(L*, a*, b*).
static func lab(c: Color) -> Vector3:
	var r := _linear(c.r)
	var g := _linear(c.g)
	var b := _linear(c.b)
	var x := _lab_f((0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047)
	var y := _lab_f(0.2126 * r + 0.7152 * g + 0.0722 * b)
	var z := _lab_f((0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883)
	return Vector3(116.0 * y - 16.0, 500.0 * (x - y), 200.0 * (y - z))


## The LAB hue in degrees, 0 to 360.
static func hue(v: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(v.z, v.y)), 360.0)


## The smaller angle between two hues, 0 to 180.
static func hue_gap(a: float, b: float) -> float:
	var d := fposmod(a - b, 360.0)
	return minf(d, 360.0 - d)


## CIE76 colour difference.
static func delta_e(a: Color, b: Color) -> float:
	return lab(a).distance_to(lab(b))


## A colour as a point: {"hex", "L", "a", "b", "C", "h"}, to 0.1.
static func reading(c: Color) -> Dictionary:
	var v := lab(c)
	return {
		"hex": "#" + c.to_html(false).to_upper(),
		"L": snappedf(v.x, 0.1), "a": snappedf(v.y, 0.1), "b": snappedf(v.z, 0.1),
		"C": snappedf(Vector2(v.y, v.z).length(), 0.1), "h": snappedf(hue(v), 0.1),
	}


## The per-channel median of the pixels in `rect` (every `stride`th one), only those within
## `radius` of `center` when a radius is given, and the highest channel among them (0 to 255):
## {"color", "max_channel", "count"}. count is 0 when no pixel lies in the image.
static func median_of(img: Image, rect: Rect2i, stride := 1, center := Vector2.INF, radius := 0.0) -> Dictionary:
	var area := rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var r := PackedFloat32Array()
	var g := PackedFloat32Array()
	var b := PackedFloat32Array()
	var top := 0.0
	for y in range(area.position.y, area.end.y, stride):
		for x in range(area.position.x, area.end.x, stride):
			if radius > 0.0 and Vector2(x, y).distance_to(center) > radius:
				continue
			var c := img.get_pixel(x, y)
			r.append(c.r)
			g.append(c.g)
			b.append(c.b)
			top = maxf(top, maxf(c.r, maxf(c.g, c.b)))
	if r.is_empty():
		return {"color": Color(), "max_channel": 0, "count": 0}
	r.sort()
	g.sort()
	b.sort()
	var m := r.size() / 2
	return {"color": Color(r[m], g[m], b[m]), "max_channel": roundi(top * 255.0), "count": r.size()}


## The per-channel median of a list of colours (black for none).
static func median_color(colors: PackedColorArray) -> Color:
	if colors.is_empty():
		return Color.BLACK
	var r := PackedFloat32Array()
	var g := PackedFloat32Array()
	var b := PackedFloat32Array()
	for c in colors:
		r.append(c.r)
		g.append(c.g)
		b.append(c.b)
	r.sort()
	g.sort()
	b.sort()
	var m := colors.size() / 2
	return Color(r[m], g[m], b[m])


## The WCAG contrast ratio of two sRGB colours: 1 (the same) to 21 (black on white).
static func contrast(a: Color, b: Color) -> float:
	var la := a.srgb_to_linear().get_luminance()
	var lb := b.srgb_to_linear().get_luminance()
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## The median CIE76 between two frames' pixels in `rect` (as median_of picks them), to 0.1; NAN
## when no pixel lies in the frames.
static func median_delta_e(a: Image, b: Image, rect: Rect2i, stride := 1, center := Vector2.INF, radius := 0.0) -> float:
	var area := rect.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	var d := PackedFloat32Array()
	for y in range(area.position.y, area.end.y, stride):
		for x in range(area.position.x, area.end.x, stride):
			if radius > 0.0 and Vector2(x, y).distance_to(center) > radius:
				continue
			d.append(delta_e(a.get_pixel(x, y), b.get_pixel(x, y)))
	if d.is_empty():
		return NAN
	d.sort()
	return snappedf(d[d.size() / 2], 0.1)


## The median, 99th percentile and largest CIE76 between two frames' pixels in `rect` (every
## `stride`th one on both axes), to 0.1: {"median", "p99", "max"}; {} when no pixel lies in them.
static func delta_e_spread(a: Image, b: Image, rect: Rect2i, stride := 1) -> Dictionary:
	var area := rect.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	var d := PackedFloat32Array()
	for y in range(area.position.y, area.end.y, stride):
		for x in range(area.position.x, area.end.x, stride):
			d.append(delta_e(a.get_pixel(x, y), b.get_pixel(x, y)))
	if d.is_empty():
		return {}
	d.sort()
	return {"median": snappedf(d[d.size() / 2], 0.1), "p99": snappedf(d[mini(d.size() - 1, int(d.size() * 0.99))], 0.1),
		"max": snappedf(d[d.size() - 1], 0.1)}


## The scenes --world=`world_name` stages by default: POOL_SCENES or ENDLESS_SCENES ([] for neither).
static func scenes_for(world_name: String) -> Array[String]:
	match world_name:
		"pool":
			return POOL_SCENES.duplicate()
		"endless":
			return ENDLESS_SCENES.duplicate()
	return []


## The value at a dotted path in nested dictionaries ("lineup.cell.h"), or null.
static func value_at(readings: Dictionary, path: String) -> Variant:
	var node: Variant = readings
	for key in path.split("."):
		if not node is Dictionary or not (node as Dictionary).has(key):
			return null
		node = node[key]
	return node


## Each gate's result: the gate's fields plus "value" and "status" (pass, fail or skip). A gate
## whose scene did not run, or a parity gate without parity readings, is skipped.
static func evaluate(gates: Array, readings: Dictionary, with_parity: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for gate: Dictionary in gates:
		var result := gate.duplicate()
		var value: Variant = value_at(readings, gate.path)
		result.value = value
		if not readings.has(gate.path.get_slice(".", 0)) or (gate.get("parity", false) and not with_parity):
			result.status = "skip"
		elif not (value is float or value is int) or is_nan(float(value)):
			result.status = "fail"
		else:
			var v := float(value)
			var ok := v >= float(gate.get("min", -INF)) and v <= float(gate.get("max", INF))
			result.status = "pass" if ok else "fail"
		out.append(result)
	return out


static func _linear(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


static func _lab_f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
