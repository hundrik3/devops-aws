# Deployment and cleanup runbook

## Prerequisites and preflight

1. Run `bash scripts/setup.sh`, `make check`, and `make integration` from the repository root.
2. Review the [cost estimate](costs.md) and approve the exact spending scope before apply.
3. Connect an AWS identity securely in environment settings, or use an existing short-lived role/profile on your own workstation. Never provide keys in chat. Verify it with `aws sts get-caller-identity` locally; do not publish account details as evidence. Run `.venv/bin/python scripts/aws_preflight.py` for a read-only identity check that prints no credentials or account details. The setup does not install AWS CLI; optional resource-inspection commands below require installing it separately. Terraform uses the AWS credential provider chain.
4. Ensure the role can provision the scoped lab services, pass the EC2 role and create required service-linked roles. The EC2 application role is narrower and is created separately.
5. Confirm two AZs and the RDS MySQL 8.4 / db.t3.micro combination are available in your selected region. Set `region` and `availability_zones` together.
6. Confirm EC2 vCPU, ALB, RDS, CloudFront and WAF quotas, especially the CloudFront origin prefix-list rule weight (55).
7. Copy `infra/terraform.tfvars.example` to ignored `infra/terraform.tfvars`. Choose a unique lab name. The RDS master password is generated automatically; no password variable is required.

## Optional custom domain and HTTPS origin

Use a domain and Route53 public hosted zone you already control. Request/validate an ACM certificate for the viewer domain in us-east-1, and another certificate for the origin domain in the deployment region. Validate both using ACM's DNS validation records in your authoritative zone before applying this stack. Set `domain_name`, `hosted_zone_id`, `cloudfront_certificate_arn`, `origin_domain_name` and `alb_certificate_arn` in the local variable file. Terraform creates A aliases for viewer and origin; it does not buy a domain, create a zone or request certificates. Do not select names with existing records you need to preserve.

## Plan and deploy

```bash
export PATH=/workspace/tools/bin:$PATH
terraform -chdir=infra init -input=false -lockfile=readonly
terraform -chdir=infra plan -out=deployment.tfplan
# Review locally: plans contain sensitive operational data.
terraform -chdir=infra show deployment.tfplan
# Execute only after explicit cost approval:
terraform -chdir=infra apply deployment.tfplan
```

Do not use `-auto-approve` or run a cloud apply from CI. ALB, RDS, EC2 bootstrap and CloudFront propagation can take 15-40 minutes. Inspect failures before retrying. Keep state; never reset state to hide a partial deployment.

## Readiness and evidence

```bash
make smoke URL="$(terraform -chdir=infra output -raw site_url)"
aws elbv2 describe-target-health --target-group-arn "$(terraform -chdir=infra output -raw target_group_arn)"
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$(terraform -chdir=infra output -raw autoscaling_group_name)"
aws rds describe-db-instances --db-instance-identifier "$(terraform -chdir=infra output -raw database_identifier)"
```

Verify two healthy targets placed across the two configured AZs, RDS private/encrypted status, CloudFront HTTPS responses and a successful `/db` query. Test direct ALB bypass rejection and WAF blocking deliberately; record the request and observed response before claiming either works. Scaling policy configuration alone does not demonstrate scale-out or failure recovery. Run controlled load/failure tests only within the approved cost/safety scope. Record actual results in `docs/validation.md` with secrets, account IDs and sensitive resource identifiers removed.

## Troubleshooting

- Local bootstrap logs: use SSM Session Manager, then `sudo journalctl -u portfolio` and `/var/log/cloud-init-output.log`. Do not publish secret values or state.
- `/health` passes and `/db` fails: check RDS readiness, instance-role permissions for the exact secret ARN, security groups, database DNS and the downloaded RDS CA bundle.
- ALB targets unhealthy: confirm user-data package installation and service port 8080. Root `/health` should be reachable from ALB.
- CloudFront returns 403: check WAF metrics, origin header listener rule and active origin port/prefix-list rule.
- HTTPS origin errors: certificate must match the origin DNS name; the record must point to ALB.
- Authentication errors: verify the current role/profile, securely refresh expired credentials, and retry the affected read-only operation.

## Teardown

The default lab skips the final database snapshot and loses its data. If retention is needed, first enable `skip_final_snapshot=false` and set a unique `final_snapshot_identifier`; snapshots incur ongoing storage charges. If deletion protection is on, set it to false and apply that change before planning destruction.

```bash
terraform -chdir=infra plan -destroy -out=destroy.tfplan
terraform -chdir=infra show destroy.tfplan
terraform -chdir=infra apply destroy.tfplan
terraform -chdir=infra state list
```

Confirm state is empty and perform AWS read-only checks for the named ASG, ALB, RDS, CloudFront distribution and WAF ACL. Confirm EC2 instances terminate, managed secret lifecycle, and tagged residual log groups/snapshots. CloudFront must be disabled before AWS deletes it; Terraform handles this and may wait. An empty state is not sufficient proof if resources were removed from state manually. Preserve state until AWS checks confirm cleanup. No cleanup is claimed until performed.
