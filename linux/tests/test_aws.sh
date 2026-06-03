#!/bin/bash

# Test script for .bash_aws functions
# Tests function definitions and infrastructure dependencies

source ~/.bash_aws 2>/dev/null || { echo "Failed to source .bash_aws"; exit 1; }

PASS=0
FAIL=0

pass() {
    echo "  PASS: $1"
    ((PASS++))
}

fail() {
    echo "  FAIL: $1"
    ((FAIL++))
}

warn() {
    echo "  WARN: $1"
}

# ---------------------------------------------------------------------------
# Function definition tests
# ---------------------------------------------------------------------------
echo "=== Function Definition Tests ==="

FUNCTIONS=(
    load_env
    run_aws_cmd
    aws_command_list
    aws_set_profile
    aws_unset_profile
    aws_whoami
    aws_list_users
    aws_list_groups
    aws_list_roles
    aws_list_policies
    aws_create_user
    aws_delete_user
    aws_user_info
    aws_create_access_key
    aws_list_access_keys
    aws_delete_access_key
    aws_list_buckets
    aws_bucket_size
    aws_sync_s3
    aws_list_instances
    aws_instance_info
    aws_start_instance
    aws_stop_instance
)

for fn in "${FUNCTIONS[@]}"; do
    if declare -f "$fn" >/dev/null 2>&1; then
        pass "$fn is defined"
    else
        fail "$fn is NOT defined"
    fi
done

# ---------------------------------------------------------------------------
# Infrastructure dependency tests
# ---------------------------------------------------------------------------
echo ""
echo "=== Infrastructure Tests ==="

# AWS CLI availability
if command -v aws >/dev/null 2>&1; then
    pass "AWS CLI is installed"
    if aws --version 2>/dev/null | grep -q "aws-cli"; then
        pass "AWS CLI is functional"
    else
        fail "AWS CLI is installed but not functional"
    fi
else
    warn "AWS CLI not installed -- most functions will not work"
fi

# AWS configuration files
if [[ -f ~/.aws/config ]] || [[ -f ~/.aws/credentials ]]; then
    pass "AWS configuration files found"
else
    warn "No AWS configuration files found"
fi

# Environment variables
if [[ -n "$AWS_PROFILE" ]] || [[ -n "$AWS_DEFAULT_REGION" ]]; then
    pass "AWS environment variables are set"
else
    warn "No AWS environment variables set"
fi

# jq availability
if command -v jq >/dev/null 2>&1; then
    pass "jq is available"
else
    warn "jq not available -- some JSON parsing may not work"
fi

# AWS STS connectivity
if command -v aws >/dev/null 2>&1; then
    if aws sts get-caller-identity >/dev/null 2>&1; then
        pass "AWS credentials are working (STS)"
    else
        warn "AWS credentials not configured or not working"
    fi
else
    warn "Cannot test STS -- AWS CLI not available"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
TOTAL=$((PASS + FAIL))
echo "=== Results: $PASS passed, $FAIL failed out of $TOTAL tests ==="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
