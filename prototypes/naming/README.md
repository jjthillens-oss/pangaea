# Species naming prototype

**PROPOSED.** This is an isolated Godot 4.7.2 naming study, not wired into the game or save format. All sound tables were written for this prototype; they are not borrowed from another game or published generator.

## Run

```bash
godot --headless --path prototypes/naming --script res://run.gd -- --seed=1 --count=20 --traits=diet:herbivore,habitat:sea,size:medium,limbs:2
godot --headless --path prototypes/naming --script res://tests/run_tests.gd
```

The four traits are `diet` (`herbivore`, `carnivore`, `omnivore`), `habitat` (`sea`, `shore`, `land`), `size` (`small`, `medium`, `large`) and `limbs` (0–6). Missing keys take the runner's defaults shown above. Invalid values cause a nonzero exit. The API accepts a generation number for the short lineage label; the runner uses generation I.

## Rules and tables

- One `RandomNumberGenerator` is created per `generate_many` call and its 64-bit state is seeded directly with `seed_value`. The seed is not mixed with clock time, a chunk index or a hash. Generation consumes draws in this order for each name: genus syllables, epithet syllables and ending, then four common-name words. A blocked scientific name redraws its two pieces from that same stream. A bounded 64-attempt fallback is a fixed safe name. No other code draws randomness.
- Genus and epithet each use two or three syllables. Every syllable has one onset and one vowel nucleus (`a e i o u ae ia ou`), followed by zero or one coda (`l m n r s t`). The first onset is biased by habitat: softer `l m n r s v w` at sea, `b d l m p r t` at shore, and harder `d g k p r t z` on land. Following onsets come from the shared original table in `name_generator.gd`. At most a coda and the next onset meet, so there are never three consonants in sequence.
- The epithet ending depends on diet: herbivore `a/ena/ora`, carnivore `ax/ira/or`, omnivore `on/ula/ari`. The common name draws one word from each of size, habitat, diet and limb-count tables. Thus a sea hunter and a land grazer differ visibly and in the opening sound pool. These are sound cues, not a taxonomy.
- The concatenated scientific name is checked case-insensitively against the local profanity block list, including substrings. The common-word tables contain no blocked terms. A lineage is `<Genus> <epithet>`; a short label is `<Genus> <Roman generation>` for generations 1–3999.

## Seed 1 samples

The following are the first 20 results in each habitat with default herbivore, medium size and two limbs. Each row shows `genus | common name | lineage | short label`.

### Sea

```text
Laemdepon | Soft Current Grazer Strider | Laemdepon wilvaeriaa | Laemdepon I
Riapimron | Soft Current Browser Strider | Riapimron sugaena | Riapimron I
Saepomdou | Mottled Current Grazer Strider | Saepomdou riltoora | Saepomdou I
Niatolko | Broad Reef Browser Strider | Niatolko masdortesena | Niatolko I
Lipaet | Broad Current Grazer Darter | Lipaet wiangiambuora | Lipaet I
Laefol | Mottled Current Grazer Darter | Laefol niamaesloumora | Laefol I
Nambetpel | Mottled Tide Browser Strider | Nambetpel nandomsoa | Nambetpel I
Rasdu | Soft Reef Browser Strider | Rasdu siazimtoora | Rasdu I
Votfa | Soft Reef Forager Strider | Votfa sishaveena | Votfa I
Naeretnael | Broad Current Browser Strider | Naeretnael relvoutmerora | Naeretnael I
Raerutmo | Broad Current Browser Darter | Raerutmo riaskodiaora | Raerutmo I
Vitwarmou | Soft Tide Grazer Darter | Vitwarmou limliarora | Vitwarmou I
Maesbam | Soft Tide Browser Darter | Maesbam miatdasena | Maesbam I
Limpulam | Mottled Current Browser Strider | Limpulam naetdarpota | Limpulam I
Larrian | Soft Current Forager Darter | Larrian wountima | Larrian I
Wakusiat | Mottled Tide Forager Strider | Wakusiat nesotnoma | Wakusiat I
Riafan | Soft Tide Browser Strider | Riafan vaemfula | Riafan I
Nirbal | Broad Current Grazer Darter | Nirbal somgouora | Nirbal I
Naekae | Broad Tide Browser Strider | Naekae voswimhouena | Naekae I
Rialhoutvo | Mottled Tide Grazer Darter | Rialhoutvo viarhaa | Rialhoutvo I
```

### Shore

```text
Baemdepon | Soft Foam Grazer Strider | Baemdepon tilvaeriaa | Baemdepon I
Miapimron | Soft Foam Browser Strider | Miapimron pugaena | Miapimron I
Paepomdou | Mottled Foam Grazer Strider | Paepomdou miltoora | Paepomdou I
Liatolko | Broad Estuary Browser Strider | Liatolko dasdortesena | Liatolko I
Bipaet | Broad Foam Grazer Darter | Bipaet tiangiambuora | Bipaet I
Baefol | Mottled Foam Grazer Darter | Baefol liamaesloumora | Baefol I
Lambetpel | Mottled Dune Browser Strider | Lambetpel landomsoa | Lambetpel I
Masdu | Soft Estuary Browser Strider | Masdu piazimtoora | Masdu I
Rotfa | Soft Estuary Forager Strider | Rotfa pishaveena | Rotfa I
Laeretnael | Broad Foam Browser Strider | Laeretnael melvoutmerora | Laeretnael I
Maerutmo | Broad Foam Browser Darter | Maerutmo miaskodiaora | Maerutmo I
Ritwarmou | Soft Dune Grazer Darter | Ritwarmou bimliarora | Ritwarmou I
Daesbam | Soft Dune Browser Darter | Daesbam diatdasena | Daesbam I
Bimpulam | Mottled Foam Browser Strider | Bimpulam laetdarpota | Bimpulam I
Barrian | Soft Foam Forager Darter | Barrian tountima | Barrian I
Takusiat | Mottled Dune Forager Strider | Takusiat lesotnoma | Takusiat I
Miafan | Soft Dune Browser Strider | Miafan raemfula | Miafan I
Lirbal | Broad Foam Grazer Darter | Lirbal pomgouora | Lirbal I
Laekae | Broad Dune Browser Strider | Laekae roswimhouena | Laekae I
Mialhoutvo | Mottled Dune Grazer Darter | Mialhoutvo riarhaa | Mialhoutvo I
```

### Land

```text
Daemdepon | Soft Grove Grazer Strider | Daemdepon zilvaeriaa | Daemdepon I
Piapimron | Soft Grove Browser Strider | Piapimron rugaena | Piapimron I
Raepomdou | Mottled Grove Grazer Strider | Raepomdou piltoora | Raepomdou I
Kiatolko | Broad Ridge Browser Strider | Kiatolko gasdortesena | Kiatolko I
Dipaet | Broad Grove Grazer Darter | Dipaet ziangiambuora | Dipaet I
Daefol | Mottled Grove Grazer Darter | Daefol kiamaesloumora | Daefol I
Kambetpel | Mottled Meadow Browser Strider | Kambetpel kandomsoa | Kambetpel I
Pasdu | Soft Ridge Browser Strider | Pasdu riazimtoora | Pasdu I
Totfa | Soft Ridge Forager Strider | Totfa rishaveena | Totfa I
Kaeretnael | Broad Grove Browser Strider | Kaeretnael pelvoutmerora | Kaeretnael I
Paerutmo | Broad Grove Browser Darter | Paerutmo piaskodiaora | Paerutmo I
Titwarmou | Soft Meadow Grazer Darter | Titwarmou dimliarora | Titwarmou I
Gaesbam | Soft Meadow Browser Darter | Gaesbam giatdasena | Gaesbam I
Dimpulam | Mottled Grove Browser Strider | Dimpulam kaetdarpota | Dimpulam I
Darrian | Soft Grove Forager Darter | Darrian zountima | Darrian I
Zakusiat | Mottled Meadow Forager Strider | Zakusiat kesotnoma | Zakusiat I
Piafan | Soft Meadow Browser Strider | Piafan taemfula | Piafan I
Kirbal | Broad Grove Grazer Darter | Kirbal romgouora | Kirbal I
Kaekae | Broad Meadow Browser Strider | Kaekae toswimhouena | Kaekae I
Pialhoutvo | Mottled Meadow Grazer Darter | Pialhoutvo tiarhaa | Pialhoutvo I
```
