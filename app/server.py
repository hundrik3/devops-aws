"""Small two-tier demonstration service; credentials never enter responses or logs."""
import json
import os
import ssl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import boto3
import pymysql


def database_probe():
    client = boto3.client("secretsmanager", region_name=os.environ["AWS_REGION"])
    secret = json.loads(client.get_secret_value(SecretId=os.environ["DB_SECRET_ARN"])["SecretString"])
    context = ssl.create_default_context(cafile=os.environ.get("DB_CA_FILE"))
    with pymysql.connect(host=os.environ["DB_HOST"], user=secret["username"],
                         password=secret["password"], database="portfolio", ssl=context,
                         connect_timeout=5, read_timeout=5, write_timeout=5) as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            if cursor.fetchone() != (1,):
                raise RuntimeError("Unexpected database response")
    return {"database": "reachable", "query": "SELECT 1"}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            status, body = 200, {"status": "ok"}
        elif self.path == "/":
            status, body = 200, {"project": "AWS two-tier Terraform lab", "tier": "web"}
        elif self.path == "/db":
            try:
                status, body = 200, database_probe()
            except Exception:
                status, body = 503, {"database": "unavailable"}
        else:
            status, body = 404, {"error": "not found"}
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8080"))), Handler).serve_forever()
