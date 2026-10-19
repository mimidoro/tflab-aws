#!/usr/bin/env bash
# Stand up the whole lab: both regions, failover DNS, platform and app (~30-40 min).
# Usage: scripts/up.sh [image_tag]   (default: current git commit, which must already be built)
. "$(dirname "$0")/lib.sh"

TAG="${1:-$(git -C "$REPO_ROOT" rev-parse HEAD)}"

say "Checking images tflab/web:$TAG and tflab/api:$TAG exist in ECR"
for repo in tflab/web tflab/api; do
  aws ecr describe-images --region ap-southeast-2 --repository-name "$repo" \
    --image-ids imageTag="$TAG" >/dev/null 2>&1 || die "$repo:$TAG not built - run the build workflow (or make build) first"
done
ok "images present"

say "terraform apply (both regions)"
tf_init
terraform -chdir="$REPO_ROOT/infra" apply -input=false -auto-approve -var "image_tag=$TAG"

say "Waiting for $APP_URL/api/ready"
for _ in $(seq 1 60); do
  if curl -fsS --max-time 5 "$APP_URL/api/ready" >/dev/null 2>&1; then
    ok "lab is up - serving from: $(serving_region)"
    exit 0
  fi
  sleep 10
done
die "app not ready after 10 min - check: kubectl -n app get pods, and ALB target health"
