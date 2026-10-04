TF ?= /workspace/tools/bin/terraform
PY ?= .venv/bin/python
.PHONY: setup check integration smoke
setup:
	bash scripts/setup.sh
check:
	$(TF) -chdir=infra fmt -check -recursive
	$(TF) -chdir=infra validate
	$(TF) -chdir=infra test
	$(PY) -m pytest tests/test_app.py -q
integration:
	RUN_MYSQL_INTEGRATION=1 $(PY) -m pytest tests/test_database_integration.py -q
smoke:
	$(PY) scripts/smoke.py "$(URL)"
