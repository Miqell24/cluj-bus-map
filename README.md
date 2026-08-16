# Cluj-Napoca Public Transport — interactive map

Interactive, poster-grade map of the public transport network of
**Cluj-Napoca**: Compania de Transport Public Cluj-Napoca (CTP)'s buses, trolleybuses and trams — 107 lines drawn along the
real street and track geometry.

## Live

Not published — this map is built and reviewed locally.

One feed covers everything, split by `route_type` at build time:

| mode | route_type | lines | graph |
|---|---|---|---|
| buses | 3 | city, night (N) and metropolitan lines | OSM roadways |
| trolleybuses | 11 | 1, 3, 4, 5, 6, 7, 8, 23, 25, 25N and the rest — drawn green on the bus network | OSM roadways |
| trams | 0 | 100, 101, 102 and 102L | `railway=tram` tracks |

Cluj-Napoca has **no metro**, so the engine's metro treatment stays unused.

Build quirks worth knowing:

* **Line 2 is defined but never runs.** The trolleybus Ion Mester – P-ța Gării has a `routes.txt` entry and zero trips, so it is absent from the map — 107 of the feed's 108 lines are drawn.

* **Eighteen lines run one way only**, and that is the feed's own shape: CTP publishes many metropolitan and night services as a single direction with distinct end stops, modelling the return as its own route entry — the *Plecare* / *Sosire* (departure / arrival) suffixes on the stop names are the tell.
* **Line numbers are unique across the modes**, so the line keys are the bare
  numbers printed on the vehicles — none of the mode prefixes the Sofia sibling
  needs. Re-check on every feed refresh.
* **Romanian is written in the Latin alphabet**, so this map runs without the
  second, transliterated label line its Greek, Bulgarian and Serbian siblings
  carry, and the stop names arrive properly cased and accented from the
  operator.
* **The feed's own `route_color` is ignored**, as everywhere in this family:
  colour means the MODE — navy bus, green trolleybus, red tram.

## Pipeline

`npm run download` fetches the GTFS, the OSM roadways, the tram tracks and
MapLibre GL. `npm run build` map-matches every line (HMM/Viterbi on the OSM
graphs) and writes GeoJSON to `data/out/`. `npm run serve` hosts the map at
http://localhost:8144.

Data: Compania de Transport Public Cluj-Napoca (CTP) · base map © OpenFreeMap / OpenMapTiles / OpenStreetMap
contributors.
