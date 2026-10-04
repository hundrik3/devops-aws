import importlib.util
import json
import threading
from http.server import ThreadingHTTPServer
from pathlib import Path
from unittest.mock import MagicMock

import pytest
import requests

spec = importlib.util.spec_from_file_location("app", Path(__file__).parents[1] / "app/server.py")
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)

@pytest.fixture
def service():
    server = ThreadingHTTPServer(("127.0.0.1", 0), app.Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield f"http://127.0.0.1:{server.server_port}"
    server.shutdown()
    server.server_close()
    thread.join()

@pytest.mark.parametrize("path,status,key,value", [
    ("/", 200, "tier", "web"), ("/health", 200, "status", "ok"),
    ("/missing", 404, "error", "not found")])
def test_http_routes(service, path, status, key, value):
    response = requests.get(service + path, timeout=5)
    assert response.status_code == status
    assert response.json()[key] == value
    assert response.headers["Cache-Control"] == "no-store"

def test_database_failure_is_sanitized(service, monkeypatch):
    def fail():
        raise RuntimeError("password=DO_NOT_LEAK")
    monkeypatch.setattr(app, "database_probe", fail)
    response = requests.get(service + "/db", timeout=5)
    assert response.status_code == 503
    assert response.json() == {"database": "unavailable"}
    assert "DO_NOT_LEAK" not in response.text

def test_database_success_route(service, monkeypatch):
    monkeypatch.setattr(app, "database_probe", lambda: {"database": "reachable", "query": "SELECT 1"})
    response = requests.get(service + "/db", timeout=5)
    assert response.status_code == 200
    assert response.json()["database"] == "reachable"

def test_database_probe_uses_tls_and_secret(monkeypatch):
    for key, value in {"AWS_REGION": "us-east-1", "DB_HOST": "db.example", "DB_SECRET_ARN": "arn:test"}.items():
        monkeypatch.setenv(key, value)
    client = MagicMock()
    client.get_secret_value.return_value = {"SecretString": json.dumps({"username": "test", "password": "test-only"})}
    monkeypatch.setattr(app.boto3, "client", lambda *a, **kw: client)
    connect = MagicMock()
    cursor = connect.return_value.__enter__.return_value.cursor.return_value.__enter__.return_value
    cursor.fetchone.return_value = (1,)
    monkeypatch.setattr(app.pymysql, "connect", connect)
    assert app.database_probe()["database"] == "reachable"
    client.get_secret_value.assert_called_once_with(SecretId="arn:test")
    cursor.execute.assert_called_once_with("SELECT 1")
    assert connect.call_args.kwargs["ssl"].check_hostname
    assert connect.call_args.kwargs["ssl"].verify_mode == app.ssl.CERT_REQUIRED
