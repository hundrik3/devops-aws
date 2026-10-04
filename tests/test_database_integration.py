"""Opt-in integration: real MySQL/TLS, only Secrets Manager is replaced locally."""
import importlib.util
import json
import os
from pathlib import Path
import secrets
import subprocess
import threading
import time
from http.server import ThreadingHTTPServer

import pytest
import requests

pytestmark = pytest.mark.skipif(os.environ.get('RUN_MYSQL_INTEGRATION') != '1', reason='Set RUN_MYSQL_INTEGRATION=1; requires Docker and OpenSSL')
spec = importlib.util.spec_from_file_location('integration_app', Path(__file__).parents[1] / 'app/server.py')
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)


def test_real_mysql_tls_http(tmp_path, monkeypatch):
    tmp_path.chmod(0o755)
    key, cert = tmp_path / 'server.key', tmp_path / 'server.crt'
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                    '-keyout', str(key), '-out', str(cert), '-days', '1',
                    '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
                   check=True, capture_output=True)
    cert.chmod(0o644)
    key.chmod(0o644)  # disposable local test key; readable by the container's MySQL user
    password = secrets.token_urlsafe(24)
    env = tmp_path / 'mysql.env'
    env.write_text(f'MYSQL_ROOT_PASSWORD={secrets.token_urlsafe(24)}\nMYSQL_DATABASE=portfolio\nMYSQL_USER=portfolio_user\nMYSQL_PASSWORD={password}\n')
    env.chmod(0o600)
    name = 'portfolio-test-' + secrets.token_hex(6)
    try:
        subprocess.run(['docker', 'run', '-d', '--name', name, '-p', '127.0.0.1::3306',
                        '--env-file', str(env), '-v', f'{tmp_path}:/tls:ro', 'mysql:8.4@sha256:6ea90827b1100f8f2ae306a539f86d2c264a26ed435a2a9f75551dd5c3aeb242',
                        '--ssl-cert=/tls/server.crt', '--ssl-key=/tls/server.key',
                        '--require-secure-transport=ON'], check=True, capture_output=True)
        port = int(subprocess.check_output(['docker', 'port', name, '3306/tcp'], text=True).strip().rsplit(':', 1)[1])
        for k, v in {'AWS_REGION': 'us-east-1', 'DB_HOST': 'localhost', 'DB_SECRET_ARN': 'local-test', 'DB_CA_FILE': str(cert)}.items():
            monkeypatch.setenv(k, v)
        class LocalSecret:
            def get_secret_value(self, **kwargs):
                assert kwargs == {'SecretId': 'local-test'}
                return {'SecretString': json.dumps({'username': 'portfolio_user', 'password': password})}
        monkeypatch.setattr(app.boto3, 'client', lambda *a, **kw: LocalSecret())
        original_connect = app.pymysql.connect
        monkeypatch.setattr(app.pymysql, 'connect', lambda **kw: original_connect(port=port, **kw))
        deadline = time.monotonic() + 120
        while True:
            try:
                assert app.database_probe()['database'] == 'reachable'
                break
            except Exception:
                if time.monotonic() >= deadline:
                    logs = subprocess.run(['docker', 'logs', name], capture_output=True, text=True)
                    safe = '\n'.join(line for line in (logs.stdout + logs.stderr).splitlines() if any(word in line.lower() for word in ['ssl', 'tls', 'certificate', '[error]']) and 'password' not in line.lower())
                    pytest.fail('MySQL did not become ready: ' + safe)
                time.sleep(2)
        # Verify that the connection really negotiated TLS.
        with original_connect(host='localhost', port=port, user='portfolio_user', password=password,
                              database='portfolio', ssl=app.ssl.create_default_context(cafile=str(cert))) as conn:
            with conn.cursor() as cursor:
                cursor.execute("SHOW STATUS LIKE 'Ssl_cipher'")
                assert cursor.fetchone()[1]
        with pytest.raises(app.pymysql.MySQLError):
            original_connect(host='localhost', port=port, user='portfolio_user', password=password,
                             database='portfolio', ssl=app.ssl.create_default_context())
        server = ThreadingHTTPServer(('127.0.0.1', 0), app.Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            response = requests.get(f'http://127.0.0.1:{server.server_port}/db', timeout=10)
            assert response.status_code == 200
            assert response.json() == {'database': 'reachable', 'query': 'SELECT 1'}
            assert password not in response.text
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
    finally:
        subprocess.run(['docker', 'rm', '-f', '-v', name], capture_output=True)

        env.unlink(missing_ok=True)
        key.unlink(missing_ok=True)
        cert.unlink(missing_ok=True)
