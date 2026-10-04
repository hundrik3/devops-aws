# Cost estimate and spending boundary

Region: us-east-1. Approximate on-demand planning range, 730 hours/month, low traffic, no free-tier or credit assumptions. These are budget estimates, not a live AWS Pricing API quote; confirm current prices before deployment.

| Resource | Default quantity | Approximate monthly USD |
|---|---:|---:|
| EC2 t3.micro | 2 (maximum 3 under scaling) | 15-23 |
| Encrypted EC2 gp3 root volumes | 2 x 8 GiB | 1-2 |
| RDS MySQL db.t3.micro | 1, Single-AZ | 13-26 |
| RDS gp3 storage | 20 GiB | 2-3 |
| ALB | 1 + light LCU usage | 17-23 |
| Public IPv4 | about 4: 2 EC2 + at least 2 ALB | 15+, scales with ALB addresses |
| AWS WAF | 1 ACL, 2 rules + requests | 7+ |
| Secrets Manager | 1 RDS-managed secret + reads | 1+ |
| CloudFront, logs, backups, transfer | usage-dependent | 0-10+ |

Budget roughly **USD 80-120/month** at low usage, or **USD 0.11-0.17/hour** averaged over a month. A two-hour smoke-test lab should normally be around **USD 1-3**, allowing for rounding, temporary resources and logs. A proposed **USD 5 test budget is a planning limit, not an AWS-enforced spending cap**. Unexpected traffic, data transfer, T3 surplus CPU credits, retries, extra public IPs, snapshots or retained resources can increase cost.

No NAT Gateway, domain purchase, hosted-zone creation, Aurora cluster or additional paid WAF subscription is part of the default deployment. Existing Route53 records/certificates are optional; a new hosted zone/domain would add separate charges and requires separate approval. Multi-AZ RDS materially increases database cost.

No cloud creation is allowed without explicit spending consent. Inspect the real Terraform plan for resource counts and names before apply. Default scope: one VPC, four subnets, an Internet gateway and route tables, three security groups and rules, one ALB/listener/target group, one launch template and 2-3 EC2 instances, IAM role/profile/policies, one RDS instance/subnet group/parameter group/managed secret, one CloudFront distribution, one WAF ACL/two rules, and autoscaling policy/associated CloudWatch alarms.

## Price references

- [EC2 pricing](https://aws.amazon.com/ec2/pricing/on-demand/)
- [RDS MySQL pricing](https://aws.amazon.com/rds/mysql/pricing/)
- [Elastic Load Balancing](https://aws.amazon.com/elasticloadbalancing/pricing/)
- [Public IPv4 pricing](https://aws.amazon.com/vpc/pricing/)
- [WAF pricing](https://aws.amazon.com/waf/pricing/)
- [CloudFront pricing](https://aws.amazon.com/cloudfront/pricing/)
- [Secrets Manager pricing](https://aws.amazon.com/secrets-manager/pricing/)

After destruction, check for RDS-created Secrets Manager retention, manually retained snapshots, CloudWatch log groups and backups. Delete only confirmed lab-owned leftovers after reviewing their retention needs. Budget alerts notify; they do not guarantee a hard stop.
