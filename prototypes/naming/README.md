# Species naming prototype

**PROPOSED.** This is an isolated Godot 4.7.2 naming study, not wired into the game or save format. All sound tables were written for this prototype; they are not borrowed from another game or published generator.

## Run

```bash
godot --headless --path prototypes/naming --script res://run.gd -- --seed=1 --count=20 --traits=diet:herbivore,habitat:sea,size:medium,limbs:2
godot --headless --path prototypes/naming --script res://tests/run_tests.gd
```

The four traits are `diet` (`herbivore`, `carnivore`, `omnivore`), `habitat` (`sea`, `shore`, `land`), `size` (`small`, `medium`, `large`) and `limbs` (0–6). Missing keys take the runner's defaults shown above. Invalid values cause a nonzero exit. The API accepts a generation number for the short lineage label; the runner uses generation I.

## Rules and tables

- One `RandomNumberGenerator` is created per `generate_many` call and its 64-bit state is seeded directly with `seed_value`. The seed is not mixed with clock time, a chunk index or a hash. Habitat index × 3, diet index × 5, size index × 7 and limb count × 11 determine a fixed number of initial draws from that same stream, so traits change the whole sound sequence. Generation then consumes draws in this order for each name: genus syllables, epithet syllables and ending, then four common-name words. A blocked scientific name redraws its two pieces from the same stream. A bounded 64-attempt fallback is a fixed safe name. No other code draws randomness.
- Genus and epithet each use two or three syllables. Every syllable has one onset and one vowel nucleus (`a e i o u ae ia ou`), followed by zero or one coda (`l m n r s t`). The first onset is biased by habitat: softer `l m n r s v w` at sea, `b d l m p r t` at shore, and harder `d g k p r t z` on land. Following onsets come from the shared original table in `name_generator.gd`. At most a coda and the next onset meet, so there are never three consonants in sequence.
- The epithet ending depends on diet: herbivore `a/ena/ora`, carnivore `ax/ira/or`, omnivore `on/ula/ari`. The common name draws one word from each of size, habitat, diet and limb-count tables. Thus a sea hunter and a land grazer differ visibly and in the opening sound pool. These are sound cues, not a taxonomy.
- The concatenated scientific name is checked case-insensitively against a local block list of reachable substrings, including `tit`, `ass`, `arse`, `anal`, `slut`, `damn`, `nazi`, `rape` and `hell`. Terms impossible under these sound tables are omitted. The common-word tables contain no blocked terms. A lineage is `<Genus> <epithet>`; a short label is `<Genus> <Roman generation>` for generations 1–3999.

## Seed 1 samples

The following are the first 20 results in each habitat with default herbivore, medium size and two limbs. Each row shows `genus | common name | lineage | short label`.

### Sea

```text
Maennal | Broad Tide Browser Darter | Maennal monoraelora | Maennal I
Limkus | Soft Tide Grazer Darter | Limkus rotzeora | Limkus I
Retmelsat | Mottled Reef Forager Darter | Retmelsat suvomora | Retmelsat I
Wustaen | Mottled Tide Grazer Strider | Wustaen voumembulena | Wustaen I
Lourfem | Soft Tide Browser Darter | Lourfem winkonkaora | Lourfem I
Naedillou | Soft Reef Browser Darter | Naedillou woumiaena | Naedillou I
Vobatse | Broad Reef Forager Darter | Vobatse visessolena | Vobatse I
Naedet | Soft Current Grazer Darter | Naedet vianoutena | Naedet I
Mialtial | Broad Tide Browser Darter | Mialtial vakulena | Mialtial I
Lonmaelsias | Mottled Reef Forager Darter | Lonmaelsias wetnaelena | Lonmaelsias I
Woustilou | Mottled Reef Grazer Darter | Woustilou raerutmoena | Woustilou I
Lemfihi | Mottled Tide Grazer Strider | Lemfihi vitwarmoua | Lemfihi I
Riados | Soft Reef Browser Darter | Riados maesbamena | Riados I
Lianlis | Soft Current Browser Darter | Lianlis limpulamora | Lianlis I
Nenku | Soft Reef Browser Strider | Nenku siltarriana | Nenku I
Mebet | Broad Tide Browser Darter | Mebet wakusiata | Mebet I
Wamhomaem | Soft Reef Grazer Strider | Wamhomaem riafanena | Wamhomaem I
Nouri | Broad Tide Grazer Darter | Nouri nirbala | Nouri I
Nulourful | Broad Tide Grazer Strider | Nulourful saemesena | Nulourful I
Wuldelpiam | Broad Current Forager Strider | Wuldelpiam noutvoa | Wuldelpiam I
```

### Shore

```text
Palpia | Soft Dune Grazer Strider | Palpia roraelpirora | Palpia I
Pushanou | Broad Dune Browser Strider | Pushanou louvaemretena | Pushanou I
Lilsaet | Mottled Estuary Forager Darter | Lilsaet bopaesora | Lilsaet I
Moubousgar | Mottled Estuary Browser Darter | Moubousgar mepiashourora | Moubousgar I
Daerlaem | Soft Foam Grazer Strider | Daerlaem rialdoena | Daerlaem I
Rouwekous | Mottled Foam Browser Darter | Rouwekous bagaemdoena | Rouwekous I
Taenbogos | Mottled Foam Browser Darter | Taenbogos pavortaeena | Taenbogos I
Paran | Broad Dune Forager Darter | Paran laefialtialora | Paran I
Manael | Broad Estuary Browser Strider | Manael bonmaelsiasa | Manael I
Bemdemma | Soft Estuary Browser Darter | Bemdemma riloukota | Bemdemma I
Raeslialsiar | Mottled Dune Browser Strider | Raeslialsiar dihia | Raeslialsiar I
Roumfus | Mottled Estuary Forager Strider | Roumfus diamziaa | Roumfus I
Darwilom | Broad Foam Grazer Darter | Darwilom bianlisa | Darwilom I
Diarzae | Soft Estuary Forager Strider | Diarzae pehenkuora | Diarzae I
Maelhiawou | Broad Dune Grazer Strider | Maelhiawou taemsinsuena | Maelhiawou I
Bialberaem | Soft Foam Grazer Strider | Bialberaem morpita | Bialberaem I
Tovom | Soft Dune Grazer Strider | Tovom mothiapia | Tovom I
Roswimhou | Broad Dune Forager Darter | Roswimhou rentemena | Roswimhou I
Popiarha | Broad Estuary Forager Darter | Popiarha laevoumuena | Popiarha I
Latkostian | Soft Estuary Grazer Darter | Latkostian medaa | Latkostian I
```

### Land

```text
Piavagin | Broad Ridge Browser Strider | Piavagin girderena | Piavagin I
Ganou | Broad Meadow Browser Strider | Ganou kouvaemretena | Ganou I
Kilsaet | Mottled Ridge Forager Darter | Kilsaet dopaesora | Kilsaet I
Poubousgar | Mottled Ridge Browser Darter | Poubousgar pepiashourora | Poubousgar I
Gaerlaem | Soft Grove Grazer Strider | Gaerlaem tialdoena | Gaerlaem I
Touwekous | Mottled Grove Browser Darter | Touwekous dagaemdoena | Touwekous I
Zaenbogos | Mottled Grove Browser Darter | Zaenbogos ravortaeena | Zaenbogos I
Raran | Broad Meadow Forager Darter | Raran kaefialtialora | Raran I
Panael | Broad Ridge Browser Strider | Panael donmaelsiasa | Panael I
Demdemma | Soft Ridge Browser Darter | Demdemma tiloukota | Demdemma I
Taeslialsiar | Mottled Meadow Browser Strider | Taeslialsiar gihia | Taeslialsiar I
Toumfus | Mottled Ridge Forager Strider | Toumfus giamziaa | Toumfus I
Garwilom | Broad Grove Grazer Darter | Garwilom dianlisa | Garwilom I
Giarzae | Soft Ridge Forager Strider | Giarzae rehenkuora | Giarzae I
Zitbi | Mottled Meadow Grazer Darter | Zitbi gufebetora | Zitbi I
Korzour | Broad Ridge Browser Darter | Korzour torramhoa | Korzour I
Rildi | Soft Ridge Forager Strider | Rildi gisouriora | Rildi I
Rugut | Broad Ridge Forager Darter | Rugut kulourfulora | Rugut I
Zelfusmam | Mottled Grove Browser Strider | Zelfusmam zelpiamwulora | Zelfusmam I
Koulnelkae | Mottled Grove Forager Darter | Koulnelkae dihafarora | Koulnelkae I
```
