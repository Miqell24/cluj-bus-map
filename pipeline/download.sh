#!/usr/bin/env bash
# Downloads input data: Cluj-Napoca GTFS, OSM networks (Overpass), MapLibre GL.
# Everything is cached — re-running only fetches what is missing.
#
# ONE feed covers the whole network: Compania de Transport Public Cluj-Napoca (CTP)'s
# buses and trolleybuses and trams, split by route_type at build time.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data/gtfs data/osm web/vendor

# A downloaded extract is only accepted if it PARSES and carries a plausible
# number of elements. `grep -q '"elements"'` — the guard this family used
# everywhere — passes on a truncated response too: Brașov's roads arrived as a
# 65 kB fragment that still contained the string, was taken for complete, and
# silently skipped the city (16.08.2026).
# The minimum differs by extract: a road network runs to tens of thousands of
# ways, a city tram network to a few hundred (Cluj's is 132), so the caller
# passes its own floor rather than sharing one.
ok_json () { # $1=file  $2=minimum element count
  python3 - "$1" "$2" <<'PYEOF' 2>/dev/null
import json, sys
try:
    sys.exit(0 if len(json.load(open(sys.argv[1])).get("elements", [])) >= int(sys.argv[2]) else 1)
except Exception:
    sys.exit(1)
PYEOF
}

BB=46.55,23.25,46.93,23.88

# 1) GTFS
if [ ! -f data/gtfs/routes.txt ]; then
  echo "== CTP Cluj GTFS (Cluj-Napoca) =="
  curl -fL --retry 3 --max-time 600 -o data/cluj-gtfs.zip \
    "https://external.gtfs.ro/cluj/CLUJ.zip"
  unzip -o data/cluj-gtfs.zip -d data/gtfs
fi

# 2) OSM — roadways over the feed's extent plus margin.
if [ ! -f data/osm/cluj.json ]; then
  echo "== Overpass (roads) =="
  QR="[out:json][timeout:900];way($BB)[\"highway\"~\"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|busway|construction|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)$\"];out geom;"
  ok=0
  # overpass-api.de first: the lighter mirrors have been caught serving a stale
  # database (Naples, 16.08.2026 — a line opened in 2025 was missing)
  for EP in "https://overpass-api.de/api/interpreter" \
            "https://maps.mail.ru/osm/tools/overpass/api/interpreter" \
            "https://overpass.kumi.systems/api/interpreter"; do
    echo "-- $EP"
    if curl -fsS --max-time 900 -o data/osm/cluj.json --data-urlencode "data=$QR" "$EP" \
       && ok_json "data/osm/cluj.json" 2000; then
      ok=1; break
    fi
    sleep 5
  done
  [ "$ok" = 1 ] || { echo "Overpass (roads): all mirrors failed" >&2; exit 1; }
fi

# 2b) OSM — tram tracks for the rail mode. `disused` and `construction` come
#     along on purpose: OSM lags behind reopenings, and a corridor sitting
#     under a stale lifecycle tag drops whole lines out of the graph (Belgrade,
#     16.08.2026). See railKind() in pipeline/lib/graph.mjs.
if [ ! -f data/osm/cluj-rail.json ]; then
  echo "== Overpass (tram tracks) =="
  QT="[out:json][timeout:300];way($BB)[\"railway\"~\"^(tram|construction|disused)$\"];out geom;"
  ok=0
  for EP in "https://overpass-api.de/api/interpreter" \
            "https://maps.mail.ru/osm/tools/overpass/api/interpreter" \
            "https://overpass.kumi.systems/api/interpreter"; do
    echo "-- $EP"
    if curl -fsS --max-time 300 -o data/osm/cluj-rail.json --data-urlencode "data=$QT" "$EP" \
       && ok_json "data/osm/cluj-rail.json" 40; then
      ok=1; break
    fi
    sleep 5
  done
  [ "$ok" = 1 ] || { echo "Overpass (rails): all mirrors failed" >&2; exit 1; }
fi

# 3) MapLibre GL (vendored, no CDN at runtime)
if [ ! -f web/vendor/maplibre-gl.js ]; then
  echo "== MapLibre GL =="
  curl -fL --retry 3 -o web/vendor/maplibre-gl.js  https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.js
  curl -fL --retry 3 -o web/vendor/maplibre-gl.css https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.css
fi

echo "OK — data ready:"
du -sh data/cluj-gtfs.zip data/osm/cluj*.json 2>/dev/null || true
