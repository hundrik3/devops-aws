"""Read-only functional checks against the deployed CloudFront endpoint."""
import argparse
import requests

parser = argparse.ArgumentParser()
parser.add_argument("url")
args = parser.parse_args()
assert args.url.startswith("https://"), "Use the HTTPS CloudFront endpoint"
for path, expected in [("/", "tier"), ("/health", "status"), ("/db", "database")]:
    response = requests.get(args.url.rstrip("/") + path, timeout=30)
    response.raise_for_status()
    body = response.json()
    assert body[expected] == {"tier": "web", "status": "ok", "database": "reachable"}[expected], body
    print(f"PASS {path}: {response.status_code} {body}")
response = requests.get(args.url.rstrip("/") + "/missing", timeout=30)
assert response.status_code == 404
print("PASS /missing: 404")
