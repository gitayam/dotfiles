#!/bin/bash

# Test script for .bash_aws functions
source ~/.bash_aws 2>/dev/null || { echo "Failed to source .bash_aws"; exit 1; }

echo "Testing .bash_aws functions..."

echo "Test 1: AWS CLI availability check"
if command -v aws >/dev/null 2>&1; then
    echo "✓ AWS CLI is available"
    
    # Test AWS CLI version
    if aws --version 2>/dev/null | grep -q "aws-cli"; then
        echo "✓ AWS CLI is functional"
    else
        echo "⚠ AWS CLI may not be functional"
    fi
else
    echo "⚠ AWS CLI not available - some functions will not work"
fi

echo "Test 2: aws_profile function"
if declare -f aws_profile >/dev/null; then
    echo "✓ aws_profile function is defined"
    
    # Test setting a profile (this won't actually change anything without real AWS config)
    if aws_profile default 2>/dev/null; then
        echo "✓ aws_profile function works"
    else
        echo "⚠ aws_profile function may not work (no AWS configuration)"
    fi
else
    echo "✗ aws_profile function not found"
    exit 1
fi

echo "Test 3: aws_regions function"
if declare -f aws_regions >/dev/null; then
    echo "✓ aws_regions function is defined"
else
    echo "✗ aws_regions function not found"
    exit 1
fi

echo "Test 4: aws_instances function"
if declare -f aws_instances >/dev/null; then
    echo "✓ aws_instances function is defined"
else
    echo "✗ aws_instances function not found"
    exit 1
fi

echo "Test 5: aws_s3_sync function"
if declare -f aws_s3_sync >/dev/null; then
    echo "✓ aws_s3_sync function is defined"
else
    echo "✗ aws_s3_sync function not found"
    exit 1
fi

echo "Test 6: aws_logs function"
if declare -f aws_logs >/dev/null; then
    echo "✓ aws_logs function is defined"
else
    echo "✗ aws_logs function not found"
    exit 1
fi

echo "Test 7: aws_costs function"
if declare -f aws_costs >/dev/null; then
    echo "✓ aws_costs function is defined"
else
    echo "✗ aws_costs function not found"
    exit 1
fi

echo "Test 8: aws_lambda_list function"
if declare -f aws_lambda_list >/dev/null; then
    echo "✓ aws_lambda_list function is defined"
else
    echo "✗ aws_lambda_list function not found"
    exit 1
fi

echo "Test 9: aws_rds_instances function"
if declare -f aws_rds_instances >/dev/null; then
    echo "✓ aws_rds_instances function is defined"
else
    echo "✗ aws_rds_instances function not found"
    exit 1
fi

echo "Test 10: aws_security_groups function"
if declare -f aws_security_groups >/dev/null; then
    echo "✓ aws_security_groups function is defined"
else
    echo "✗ aws_security_groups function not found"
    exit 1
fi

echo "Test 11: aws_cloudformation_stacks function"
if declare -f aws_cloudformation_stacks >/dev/null; then
    echo "✓ aws_cloudformation_stacks function is defined"
else
    echo "✗ aws_cloudformation_stacks function not found"
    exit 1
fi

echo "Test 12: aws_iam_users function"
if declare -f aws_iam_users >/dev/null; then
    echo "✓ aws_iam_users function is defined"
else
    echo "✗ aws_iam_users function not found"
    exit 1
fi

echo "Test 13: aws_vpcs function"
if declare -f aws_vpcs >/dev/null; then
    echo "✓ aws_vpcs function is defined"
else
    echo "✗ aws_vpcs function not found"
    exit 1
fi

echo "Test 14: aws_route53_zones function"
if declare -f aws_route53_zones >/dev/null; then
    echo "✓ aws_route53_zones function is defined"
else
    echo "✗ aws_route53_zones function not found"
    exit 1
fi

echo "Test 15: aws_assume_role function"
if declare -f aws_assume_role >/dev/null; then
    echo "✓ aws_assume_role function is defined"
else
    echo "✗ aws_assume_role function not found"
    exit 1
fi

echo "Test 16: AWS configuration check"
if [[ -f ~/.aws/config ]] || [[ -f ~/.aws/credentials ]]; then
    echo "✓ AWS configuration files found"
else
    echo "⚠ No AWS configuration files found - functions may not work without proper AWS setup"
fi

echo "Test 17: Environment variables check"
if [[ -n "$AWS_PROFILE" ]] || [[ -n "$AWS_DEFAULT_REGION" ]]; then
    echo "✓ AWS environment variables are set"
else
    echo "⚠ No AWS environment variables set"
fi

echo "Test 18: jq availability (required for JSON parsing)"
if command -v jq >/dev/null 2>&1; then
    echo "✓ jq is available for JSON parsing"
else
    echo "⚠ jq not available - some AWS functions may not work properly"
fi

echo "Test 19: AWS STS test (if configured)"
if command -v aws >/dev/null 2>&1; then
    if aws sts get-caller-identity >/dev/null 2>&1; then
        echo "✓ AWS credentials are working"
    else
        echo "⚠ AWS credentials not configured or not working"
    fi
else
    echo "⚠ Cannot test AWS credentials - AWS CLI not available"
fi

echo "All .bash_aws tests completed successfully!"
echo "Note: Many AWS functions require proper AWS configuration and credentials to work fully."
