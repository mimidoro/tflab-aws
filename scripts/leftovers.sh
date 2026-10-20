#!/usr/bin/env bash
# Sweep both lab regions (+ us-east-1) for anything billable left behind after teardown.
# Report-only: exits 1 if something is found. Bootstrap resources (tag Project=tflab-aws-bootstrap)
# are expected and ignored. The tagging API is eventually consistent - re-run once if in doubt.
. "$(dirname "$0")/lib.sh"

found=0

# check "<label>" "<whitespace-separated ids>"
check() {
  local label="$1" ids="$2" id
  for id in $ids; do
    [[ -z "$id" || "$id" == "None" ]] && continue
    printf '   \033[31mLEFT\033[0m %s %s\n' "$label" "$id"
    found=1
  done
}

for region in ap-southeast-2 ap-southeast-4 us-east-1; do
  say "Region $region"

  check "tagged" "$(aws resourcegroupstaggingapi get-resources --region "$region" \
    --tag-filters Key=Project,Values=tflab-aws \
    --query 'ResourceTagMappingList[].ResourceARN' --output text)"

  [[ "$region" == "us-east-1" ]] && continue

  check "EKS cluster" "$(aws eks list-clusters --region "$region" \
    --query 'clusters[?starts_with(@, `tflab-`)]' --output text)"

  check "RDS instance" "$(aws rds describe-db-instances --region "$region" \
    --query 'DBInstances[?starts_with(DBInstanceIdentifier, `tflab-`)].DBInstanceIdentifier' --output text)"

  check "ALB" "$(aws elbv2 describe-load-balancers --region "$region" \
    --query 'LoadBalancers[?starts_with(LoadBalancerName, `tflab-`)].LoadBalancerName' --output text)"

  check "EC2 instance" "$(aws ec2 describe-instances --region "$region" \
    --filters Name=instance-state-name,Values=pending,running,stopping,stopped \
              Name=tag:Project,Values=tflab-aws \
    --query 'Reservations[].Instances[].InstanceId' --output text)"

  check "unattached EBS volume" "$(aws ec2 describe-volumes --region "$region" \
    --filters Name=status,Values=available --query 'Volumes[].VolumeId' --output text)"

  check "unassociated Elastic IP" "$(aws ec2 describe-addresses --region "$region" \
    --query 'Addresses[?AssociationId==null].PublicIp' --output text)"

  check "Auto Scaling group" "$(aws autoscaling describe-auto-scaling-groups --region "$region" \
    --query 'AutoScalingGroups[?starts_with(AutoScalingGroupName, `tflab-`)].AutoScalingGroupName' --output text)"

  check "NAT gateway" "$(aws ec2 describe-nat-gateways --region "$region" \
    --filter Name=state,Values=available,pending --query 'NatGateways[].NatGatewayId' --output text)"
done

if (( found )); then
  warn "billable leftovers found - delete them or re-run scripts/down.sh"
  exit 1
fi
ok "nothing billable left"
