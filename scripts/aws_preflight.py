"""Read-only AWS authentication check without printing identity or credentials."""
import sys
import boto3
from botocore.config import Config

try:
    boto3.Session().client('sts', region_name='us-east-1',
                           config=Config(connect_timeout=10, read_timeout=10,
                                         retries={'max_attempts': 0})).get_caller_identity()
except Exception as error:
    print(f'AWS authentication check blocked: {type(error).__name__}. Configure an AWS identity securely in environment settings.')
    sys.exit(2)
print('PASS: AWS STS authenticated identity is available (identity withheld).')
