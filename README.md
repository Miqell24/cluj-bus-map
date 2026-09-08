# Cluj-Napoca Public Transport — interactive map

Interactive, poster-grade map of the public transport network of
**Cluj-Napoca**: Compania de Transport Public Cluj-Napoca (CTP)'s buses, trolleybuses and trams — 107 lines drawn along the
real street and track geometry.

## Live

Not published — this map is built and reviewed locally.

One feed covers everything, split by `route_type` at build time. Since
8.09.2026 it is the daily GTFS dump of CTP's Tranzy open-data API
([TranzyGTFSconverter](https://github.com/FloreaCostinMario/TranzyGTFSconverter),
`Output/CTP Cluj.zip`; the API itself needs a personal key). The earlier
`external.gtfs.ro/cluj/CLUJ.zip` modelled eighteen lines as one direction only
and expired on 30.06.2026.

| mode | route_type | lines | graph |
|---|---|---|---|
| buses | 3 | city, night (N) and metropolitan lines | OSM roadways |
| trolleybuses | 11 | 1, 3, 4, 5, 6, 7, 8, 23, 25, 25N and the rest — drawn green on the bus network | OSM roadways |
| trams | 0 | 100, 101, 102 and 102L | `railway=tram` tracks |

Cluj-Napoca has **no metro**, so the engine's metro treatment stays unused.

Build quirks worth knowing:

* **The feed lists 172 routes, the map draws 107.** The Tranzy dump carries
  every route the fleet system knows: pupil transports (TE1–TE14, M75A–M80),
  Emerson factory shuttles (88A–88L, 89S), festival and cemetery specials
  (30U, 8S, 39S) and dormant entries (trolleybus 2, 4N, the M…N night lines).
  `download.sh` fetches CTP's own timetable CSVs
  (`ctpcj.ro/orare/csv/orar_<line>_{lv,s,d}.csv`) into `data/roster.json`, and
  a line is drawn only when at least one of them carries a departure.
* **No calendar, no times.** The dump has one trip and one shape per
  direction and no `stop_times` clock — nothing this map reads, but trip
  counts in `meta.json` say nothing about frequency here.
* **Both directions everywhere.** The old gtfs.ro feed modelled M22, M26,
  M52, 10, 12, 29S and twelve more as a single direction with *Plecare* /
  *Sosire* end stops; the Tranzy dump carries the return leg of each.
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
