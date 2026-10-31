import json
import urllib.request
import time
import sys

sys.stdout.reconfigure(encoding='utf-8')

def main():
    with open('assets/data/bannu_places.json', 'r', encoding='utf-8') as f:
        places = json.load(f)

    print(f"Loaded {len(places)} locations from bannu_places.json\n")
    print("Sampling key locations and checking their real-world resolution on OpenStreetMap:\n")

    # Sample landmarks
    sample_indices = [0, 1, 2, 9, 15, 17, 31, 39]
    for idx in sample_indices:
        p = places[idx]
        name = p['name']
        lat, lng = p['lat'], p['lng']
        google_maps_url = f"https://www.google.com/maps?q={lat},{lng}"
        
        osm_url = f"https://nominatim.openstreetmap.org/reverse?format=json&lat={lat}&lon={lng}&zoom=17"
        req = urllib.request.Request(osm_url, headers={'User-Agent': 'ShanGoInspector/1.0'})
        resolved_address = "N/A"
        try:
            with urllib.request.urlopen(req, timeout=5) as res:
                data = json.loads(res.read().decode())
                resolved_address = data.get('display_name', 'Not found')
        except Exception as e:
            resolved_address = f"Network note: {e}"

        print(f"Place: {name}")
        print(f"  Coordinates : {lat}, {lng}")
        print(f"  Google Maps : {google_maps_url}")
        print(f"  OSM Resolved: {resolved_address[:90]}...")
        print("-" * 60)
        time.sleep(1) # respectful rate limit for OSM Nominatim

if __name__ == '__main__':
    main()
