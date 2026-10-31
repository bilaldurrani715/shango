import urllib.request
import json
import sys

sys.stdout.reconfigure(encoding='utf-8')

queries = [
    "Khalifa Gul Nawaz",
    "KGN Hospital Bannu",
    "Bannu Medical College",
    "Teaching Hospital Bannu",
    "Akram Khan Durrani College Bannu"
]

for q in queries:
    url = f"https://nominatim.openstreetmap.org/search?q={urllib.parse.quote(q)}&format=json&addressdetails=1"
    req = urllib.request.Request(url, headers={'User-Agent': 'ShanGoInspector/1.0'})
    try:
        with urllib.request.urlopen(req) as res:
            data = json.loads(res.read().decode())
            print(f"\n--- Results for '{q}': ---")
            for item in data[:3]:
                print(f"  {item.get('display_name')} -> lat: {item.get('lat')}, lon: {item.get('lon')}")
    except Exception as e:
        print(f"Error querying {q}: {e}")
