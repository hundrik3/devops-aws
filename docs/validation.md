# Validation evidence

Validation date: 2026-10-04. Environment: Linux x86_64, Python 3.12.14, Terraform 1.13.5, Docker 28.4.0. Provider lock: AWS 6.67.0 and Random 3.9.1, installed with HashiCorp signature verification. No AWS resources were created during these checks.

| Check | Actual result | Scope |
|---|---|---|
| `bash scripts/setup.sh` | Passed, including repeat execution | Checksum-verified Terraform, complete Python dependency lock, read-only provider lock installation |
| `terraform -chdir=infra fmt -check -recursive` | Passed | Terraform formatting |
| `terraform -chdir=infra validate` | Passed | Real installed provider schemas and module configuration |
| `terraform -chdir=infra test` | 6 passed, 0 failed | Mocked providers: network isolation, encrypted/private RDS, full module wiring, compute security, CloudFront/WAF, expected rejection of duplicate AZs |
| `.venv/bin/python -m pytest tests/test_app.py -q` | 6 passed, 0 failed | Real local HTTP requests; Secrets Manager/database calls mocked in unit tests |
| `make integration` | 1 passed, 0 failed (16.52 seconds) | Real MySQL 8.4, verified TLS, nonempty negotiated cipher, `SELECT 1`, successful HTTP `/db`, rejection of untrusted certificate; only Secrets Manager stubbed |
| `.venv/bin/pip check` | Passed | No broken Python dependencies |
| `bash -n scripts/setup.sh` | Passed | Installer shell syntax |
| Rendered EC2 user-data `bash -n` | Passed | Shell syntax only; package installation and systemd startup on EC2 remain unrun |
| Credential/private-key pattern scan | Passed on 29 project files | Heuristic scan before staging; no AWS keys, GitHub tokens or PEM private keys matched |
| AWS credential discovery | Blocked: `ProfileNotFound` | Environment contains a platform no-identity profile; no usable AWS authentication established |
| Authenticated AWS `terraform plan` | Not run | Requires a usable AWS identity and service API connectivity |
| AWS apply, public smoke checks, WAF bypass tests, real scaling/failover | Not run | Requires explicit cost approval and AWS access |
| AWS destroy and residual-resource audit | Not run | No cloud deployment exists to destroy |
| GitHub Actions hosted run | Not verified in this report | Workflow is included; local executions above are the evidence |

## Integration details

MySQL image: `mysql:8.4@sha256:6ea90827b1100f8f2ae306a539f86d2c264a26ed435a2a9f75551dd5c3aeb242`.

The test generates disposable credentials and a local certificate outside the repository, binds a random port to loopback, supplies the credentials through a temporary Docker env file, and removes its container, anonymous volumes and temporary credential/certificate files in teardown. The final successful run left no running project test container. The local test certificate is trusted explicitly only for that local test; production uses the AWS RDS CA bundle with hostname verification.

Initial checks exposed invalid synthetic AWS identifiers in Terraform mocks and unreadable certificate permissions in the local container fixture. Those fixture issues were corrected and the affected tests rerun successfully. TLS verification remained enabled. The application did not require disabling certificate validation.

## Interpretation

This evidence demonstrates local development readiness, infrastructure schema validity, mocked security contracts and a real application-to-MySQL TLS request path. It does **not** establish that AWS accepted the infrastructure, EC2 bootstrap succeeded, RDS/CloudFront quotas are sufficient, WAF blocks real attacks, autoscaling responds to load or cloud cleanup works. Those outcomes must be added only after deployment and direct checks in the target account.

The source assignment's AWS deployment remains pending. The repository intentionally documents that boundary instead of presenting local mocks as cloud success.
