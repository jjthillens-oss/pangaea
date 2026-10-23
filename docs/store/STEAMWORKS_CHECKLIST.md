# Steamworks checklist (owner account steps)

**Status: PROPOSED.** These steps need Joshua's own Steam account, identity, tax and bank details, so the studio
cannot do them. Facts were checked on partner.steamgames.com on 2026-10-23; Valve changes them, so re-check each step
when it comes up. Nothing in this repository is published to Steam.

Legend: **Owner** = only Joshua can do it. **Studio** = prepared in this repo for him to paste or upload.

## Phase 0: before paying anything

- [ ] **Owner:** settle the player-facing name (decision card in the "Steam store prep" thread; `docs/DECISIONS.md`
      "Product name"). Then run a trademark search (USPTO TESS for the US) and check that the Steam store, the domain
      and the main social handles are free.
- [ ] **Owner:** choose the release model: Coming Soon page now and full release later, or Early Access. It changes
      the copy, the price plan and the questions Steam asks. Recommendation: put up a Coming Soon page as soon as the
      M1 build is presentable, and decide Early Access later; wishlists build while the page is up.
- [ ] **Owner:** decide whether to sell as an individual or through a company (LLC). The legal name on the Steamworks
      account, the tax form and the bank account must match.
- [ ] **Owner:** decide the AI-content disclosure wording (`STORE_PAGE.md`, "Content survey").

## Phase 1: Steamworks onboarding (owner only)

- [ ] Sign in at partner.steamgames.com with the Steam account that will own the app (use a strong password and
      Steam Guard; consider a separate account for business).
- [ ] Digital paperwork: legal name and address, and the Steam distribution agreement.
- [ ] Identity verification.
- [ ] Tax interview (US: a W-9 as an individual or company). Valve's third-party check **may take up to 30 days**,
      so start this first.
- [ ] Bank details (routing number, account number, bank address). The account holder must match the legal name.
- [ ] Pay the **Steam Direct fee: $100 per app**, non-refundable, recouped after the game earns $1,000 in adjusted
      gross revenue. Only an admin of the Steamworks partner can pay it.
- [ ] Note the date: there is a **21-day wait** between paying the fee and being allowed to release.

## Phase 2: the app and its store page

- [ ] Create the app; note the App ID (the studio needs it for the build depots and, later, the Steam API).
- [ ] Basic info: name, developer and publisher name, genres, release date text ("Coming soon" or a quarter is fine),
      supported languages, controller support level (none until the controller work is tested).
- [ ] **Studio → Owner:** paste the short description, long description, feature bullets and tags from
      `STORE_PAGE.md`.
- [ ] **Studio → Owner:** upload the graphical assets from `docs/store/capsules/` (final versions, not the concepts).
      Store: header 920x430, small 462x174, main 1232x706, vertical 748x896, page background 1438x810 (optional),
      at least five screenshots at 1920x1080. Library: capsule 600x900, header 920x430, hero 3840x1240 (no text),
      logo (transparent PNG, up to 1280 wide or 720 tall), then choose the logo position.
- [ ] **Studio → Owner:** upload the trailer (`TRAILER_PLAN.md`).
- [ ] Content survey and rating questionnaire (Steam's IARC flow gives the regional age ratings).
- [ ] System requirements (`STORE_PAGE.md`; fill in after the minimum-spec test).
- [ ] Mark the store page **ready for review**. Submit **at least 7 business days** before you want it live.
- [ ] After approval, press **Post as Coming Soon**. The page must be public for **at least two weeks** before release.

## Phase 3: builds (when a release candidate exists)

- [ ] Depots: one Windows 64-bit depot. **Studio:** add a SteamPipe upload script (`tools/steam/`, needs the
      Steamworks SDK's `steamcmd` and the App and depot IDs; a separate task, not built yet).
- [ ] Launch option: `Pangaea.exe` (the release export; `Pangaea-dev.exe` never goes to Steam).
- [ ] Steam Cloud: decide whether to sync the save folder. The project uses a custom user directory, so on Windows
      saves live in `%APPDATA%\Pangaea\` (`project.godot`, `custom_user_dir_name`); if the name changes, decide
      whether that folder name changes too before configuring the Cloud path.
- [ ] Optional: Steamworks API features (achievements, overlay checks, rich presence) need a GDExtension such as
      GodotSteam. That is a new dependency and needs owner approval first (`CLAUDE.md`).
- [ ] Set the build live on the default branch, then request **build review** (Valve: 1 to 5 days).
- [ ] Release: press the release button once the 21-day wait, the two-week Coming Soon period and both reviews are done.

## Phase 4: after the page is live

- [ ] Steam Next Fest: sign up for the next one that falls after a demo is ready (needs a playable demo app).
- [ ] Wishlist tracking in Steamworks' reporting; the studio can summarise it on request.
- [ ] Update the page copy whenever a build adds or changes what the page promises.

## Rough timeline from "go"

| Week | What happens |
| --- | --- |
| 0 | Name and model decided; onboarding started; tax check running (up to 30 days) |
| 1 | Fee paid (21-day clock starts); app created; copy and capsules uploaded; page submitted (7 business days) |
| 2-3 | Page approved and posted as Coming Soon |
| 4+ | Earliest possible release is about 3 weeks after the fee and 2 weeks after Coming Soon, but the release date is set by the game, not the paperwork |
