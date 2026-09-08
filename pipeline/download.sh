#!/usr/bin/env bash
# Downloads input data: Cluj-Napoca GTFS, OSM networks (Overpass), MapLibre GL.
# Everything is cached — re-running only fetches what is missing.
#
# ONE feed covers the whole network: Compania de Transport Public Cluj-Napoca (CTP)'s
# buses and trolleybuses and trams, split by route_type at build time.
#
# Source (since 8.09.2026): the Tranzy open-data API of CTP Cluj (agency 2),
# dumped daily to GTFS by github.com/FloreaCostinMario/TranzyGTFSconverter
# (GitHub Action at 03:20 UTC; the API itself needs a personal key). It carries
# BOTH directions of every line with a shape each, but no calendar, no
# service_id and no times in stop_times — nothing this map reads. The earlier
# feed, https://external.gtfs.ro/cluj/CLUJ.zip, modelled 18 lines (M22, M26,
# M52, 10, 12, 29S…) as ONE direction only and expired on 30.06.2026.
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
  echo "== CTP Cluj GTFS (Cluj-Napoca, Tranzy dump) =="
  # previous source, one direction per line on 18 routes, expired 30.06.2026:
  #   https://external.gtfs.ro/cluj/CLUJ.zip
  curl -fL --retry 3 --max-time 600 -o data/cluj-gtfs.zip \
    "https://raw.githubusercontent.com/FloreaCostinMario/TranzyGTFSconverter/main/Output/CTP%20Cluj.zip"
  unzip -o data/cluj-gtfs.zip -d data/gtfs
fi

# 1b) Public-line roster from CTP's own timetables. The Tranzy dump lists every
#     route the fleet system knows — 172 of them: pupil transports (TE1–TE14,
#     M75A–M80), Emerson factory shuttles (88A–88L, 89S), festival and cemetery
#     specials (30U, 8S, 39S) and dormant entries (2, 4N, M26N…). CTP publishes
#     one CSV per line and day type at ctpcj.ro/orare/csv/orar_<L>_{lv,s,d}.csv;
#     a line counts as public when at least one of them carries an HH:MM
#     departure row (a file that only says "Nu circula" does not). build.mjs
#     reads the result from data/roster.json and draws nothing else.
if [ ! -f data/roster.json ]; then
  echo "== CTP timetables (public-line roster) =="
  python3 - <<'PYEOF'
import csv, json, re, time, urllib.request, urllib.parse, urllib.error, sys
names = sorted({(r.get('route_short_name') or '').strip()
                for r in csv.DictReader(open('data/gtfs/routes.txt', encoding='utf-8-sig', newline=''))} - {''})
roster, errors = {}, []
for n in names:
    roster[n] = {}
    for day in ('lv', 's', 'd'):
        url = f"https://ctpcj.ro/orare/csv/orar_{urllib.parse.quote(n)}_{day}.csv"
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'}), timeout=60) as r:
                body = r.read().decode('utf-8', 'replace')
            roster[n][day] = len(re.findall(r'^\s*\d{1,2}:\d{2}', body, re.M))
        except urllib.error.HTTPError as e:
            if e.code == 404: roster[n][day] = None
            else: errors.append((n, day, e.code))
        except Exception as e:
            errors.append((n, day, str(e)[:80]))
        time.sleep(0.05)
if errors:
    print('roster: %d requests failed, not caching a partial roster: %s' % (len(errors), errors[:5]), file=sys.stderr)
    sys.exit(1)
pub = [n for n, d in roster.items() if any(v for v in d.values())]
json.dump(roster, open('data/roster.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('roster: %d routes in feed, %d with a timetable file, %d public (with departures)'
      % (len(names), sum(1 for d in roster.values() if any(v is not None for v in d.values())), len(pub)))
PYEOF
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
du -sh data/cluj-gtfs.zip data/roster.json data/osm/cluj*.json 2>/dev/null || true
