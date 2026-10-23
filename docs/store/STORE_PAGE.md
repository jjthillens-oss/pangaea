# Steam store page draft

**Status: PROPOSED.** Nothing here is published. The owner approves the copy, the name and the release model before
anything goes into Steamworks. Steam's own rules quoted here were checked on 2026-10-23 at partner.steamgames.com;
re-check them when the page is set up.

## Ground rules for every store text and image

- Never name Spore, EA, Maxis or any other game, in the copy, the tags, the capsules or the trailer. No "Spore-like",
  "spiritual successor" or "from the makers of" lines. The comparison helps us internally; on the store it invites a
  trademark complaint and sets the wrong expectation.
- Describe what the build contains. The game today is the cell stage (M1). The other six eras are plans, so the copy
  sells the vision as a direction and says plainly what is playable. Steam reviews and refund requests punish a page
  that promises more than the build has.
- Capsules carry the key art and the title only: no quotes, awards, "Early Access" banners or other text (Steam rule).
- Screenshots show gameplay only: no concept art, renders or marketing text (Steam rule). At least five, 1920x1080,
  and at least four marked "suitable for all ages".

## Name

The player-facing name is still open (`docs/DECISIONS.md`, "Product name"). The drafts use **Pangaea** as a placeholder.
A quick search (2026-10-23) found two Steam games with near-identical names: *Pangea* (Hommer Games, 2021, strategy)
and *Pangea Survival* (2020, dinosaur survival). A plain "Pangaea" will share search results with them, so the
recommendation is the name plus a distinctive subtitle, followed by a proper trademark search before the page goes
live. The owner has a decision card for this.

## Short description (Steam limit: 300 characters)

Recommended (231 characters):

> Begin as a single cell in a glowing drop of water. Every part you add changes how your creature swims, feeds and
> survives, and every choice is carried forward by your lineage. Guide one line of life from the first spark toward
> the stars.

Alternative, more playful (186 characters):

> Grow a tiny, big-eyed cell into a lineage that remembers everything. Build bodies that work, outswim what hunts you,
> and carry each generation's choices from the microscopic world toward the stars.

## About this game (long description)

Steam formats this with its own BBCode; the headings below become `[h2]` lines and the bullets `[list]`. Leave room
for 3 to 5 animated GIFs or gameplay stills between sections (see `TRAILER_PLAN.md`, "Store GIFs").

> **A life that is unmistakably yours**
>
> Pangaea is an evolution sandbox about one lineage. You start as a single cell drifting through a deep-blue
> microscopic world of glassy shells, bacteria swarms and things far larger than you. Eat, avoid what hunts you, earn
> adaptation points and pass your design to the next generation. Your cell has a face, a temperament and a history,
> and the game remembers all of it.
>
> **Anatomy that matters**
>
> Every body part is a trade-off. A filter mouth sips drifting plankton; a jaw takes on carrion and prey. Spikes
> only hurt what they are pointed at. Another flagellum makes you faster, and hungrier. The editor shows you what
> each change costs before you commit, so evolving is a choice you understand, not a dice roll.
>
> **A living world with rules you can read**
>
> Predators telegraph their intent before they strike: an ambush hunter coils, a rammer puffs up before it charges.
> Food regrows when it is left alone and runs out when it is not. Survive by reading the world, not by memorising it.
>
> **Death is a setback, not an ending**
>
> When your cell dies, your lineage carries on from a fair checkpoint and you keep what you learned. Each run builds
> one continuous history.
>
> **Where this is going**
>
> The cell stage is the first of seven planned eras, from the microscopic world through the ocean, land, social
> groups, tribes and civilisations to the stars, with your lineage, its body and its relationships carried through
> every one. Each era will add a new layer on top of the last rather than replacing it.

The "Where this is going" section must change to match whatever is in the build when the page goes live. If the page
launches as Early Access, Steam also requires its own Early Access questions (why Early Access, how long, what is
planned, how the price will change); draft those once the release model is chosen.

### Feature bullets (for the bullet list under "About")

- Begin as a single expressive cell in a deep-blue microscopic world
- Body parts with real trade-offs: mouths, flagella, spikes and eye spots change speed, diet, attack and energy use
- A body editor between generations that previews every cost before you commit
- Predators with readable tells: watch for the coil and the puff, then dodge or shelter
- Lineage memory: your species, generations and points persist across deaths and saves
- Hand-built 3D art: every creature, shell and landmark is modelled in Blender, in a bright, rounded style
- An endless, growing world (planned for the cell stage): the pool scales up as your cell grows

Not yet in the build (2026-10-23): the body editor and reproduction (M1 step 4, not started; today the player picks
one of three starting bodies) and the endless world (in progress). The editor paragraph in "About" and those two
bullets depend on them. Remove or reword any line that is not in the build the page ships with.

## Tags

Steam lets the developer apply up to 20 tags; the first ones weigh most for discovery. Pick from Steam's tag picker
(names below should match it; confirm each when entering them). Ordered by priority.

| # | Tag | Why |
| --- | --- | --- |
| 1 | Simulation | Core genre |
| 2 | Sandbox | Free-form evolution |
| 3 | Character Customization | The body editor is the hook |
| 4 | Singleplayer | No multiplayer is planned (Bible section 2) |
| 5 | Colorful | Art direction |
| 6 | Cute | Big-eyed cells; matches the key art |
| 7 | Stylized | Art direction |
| 8 | Underwater | The current setting |
| 9 | Survival | Eat, avoid, recover |
| 10 | Exploration | The world to swim through |
| 11 | Procedural Generation | Seeded world |
| 12 | Nature | Theme |
| 13 | 3D | Presentation |
| 14 | Indie | Studio |
| 15 | Family Friendly | No gore; light predation only |
| 16 | Top-Down | The cell-stage camera |
| 17 | Science | Theme; evolution and microbiology |
| 18 | Relaxing | Only if play tests agree; drop if threats feel tense |

Hold back **Space, City Builder, Strategy, Base Building, God Game and Open World** until the eras that justify them
are in the build; tags that do not match the game hurt its placement and reviews. **Early Access** is applied by
Steam automatically if the release model is Early Access.

## Genres and features (Steamworks "Basic info")

- Genres: Simulation, Indie. Add Strategy only with the tribal or civilisation era.
- Features: Single-player, Steam Cloud (if the saves are wired to it; see the checklist), Full controller support only
  after the controller work lands and is tested, Steam Achievements only if built.
- Languages: English (interface, full audio: not applicable, subtitles: not applicable until there is voiced audio).

## Content survey (draft answers)

- Violence: mild, non-realistic. Cells eat other cells and plankton; predators bite and ram; no blood or gore.
- Nudity, sexual content, gambling, real-money purchases: none.
- **AI-generated content (owner decision).** Since Valve's January 2026 rewrite, code helpers no longer need to be
  disclosed, but pre-generated content players see (art, audio, text) does. Pangaea's art is authored in Blender by
  scripts that AI agents wrote under the owner's direction, and the store copy is AI-drafted. The honest reading is
  that this counts as pre-generated content, so the recommendation is to disclose it, for example: "Pangaea's code,
  3D models and text were created with AI coding agents under the developer's direction and review. Every 3D asset is
  built and finished in Blender. The game does not generate any content with AI while you play." The owner decides
  the final wording.

## System requirements (placeholder)

The minimum spec is an open decision (`docs/DECISIONS.md`). Windows 64-bit only for now. Fill in after the minimum-spec
test (Bible section 26). The owner's PC (Ryzen 7 9800X3D, RTX 5070, 32 GB) is the recommended-spec reference, not the
minimum. The renderer needs Vulkan (Forward+); the compatibility renderer covers older GPUs only if it is shipped and
tested as a fallback.

| | Minimum | Recommended |
| --- | --- | --- |
| OS | Windows 10 64-bit (to confirm) | Windows 11 64-bit |
| CPU | to measure | Ryzen 7 9800X3D class or lower, to measure |
| Memory | to measure | 16 GB |
| GPU | to measure (Vulkan 1.2 capable) | RTX 5070 class or lower, to measure |
| Storage | 1 GB (the M1 build zips to about 90 MB) | 1 GB |

## Page background and screenshots

The page background is `capsules/page_background.png` (optional; Steam generates one if it is left out). The
screenshot list is in `TRAILER_PLAN.md` ("Screenshots").
