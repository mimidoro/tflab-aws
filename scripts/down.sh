#!/usr/bin/env bash
# Teardown - memory hook "DRAIN":
#   D  Detach chaos      stop running FIS experiments, delete Chaos Mesh experiments (finalizers)
#   R  Release Helm      if a cluster is unreachable, drop its Helm releases from state
#   A  Apply destroy     terraform destroy (it removes the Melbourne replica before the Sydney primary)
#   I  Inspect leftovers scripts/leftovers.sh - fails loudly if anything billable remains
#   N  Notify            publish the result to the tflab-ops SNS topic (email)
# The bootstrap layer (state bucket, OIDC role, ECR, budget, domain) is kept on purpose.
. "$(dirname "$0")/lib.sh"

say "D  Detach chaos"
for key in syd mel; do
  region="${REGION_OF[$key]}"
  for id in $(aws fis list-experiments --region "$region" \
      --query "experiments[?state.status=='running' || state.status=='initiating'].id" --output text 2>/dev/null); do
    aws fis stop-experiment --region "$region" --id "$id" >/dev/null && ok "stopped FIS experiment $id ($key)"
  done
  if aws eks describe-cluster --region "$region" --name "${CLUSTER_OF[$key]}" >/dev/null 2>&1; then
    ctx "$key"
    k delete podchaos,networkchaos,stresschaos --all -A --wait=false >/dev/null 2>&1 || true
    k -n app delete ciliumnetworkpolicy drill-db-block --ignore-not-found >/dev/null 2>&1 || true
    ok "chaos cleared in $key"
  fi
done

say "R  Release Helm state for unreachable clusters"
tf_init
for key in syd mel; do
  if ! aws eks describe-cluster --region "${REGION_OF[$key]}" --name "${CLUSTER_OF[$key]}" >/dev/null 2>&1; then
    for addr in $(terraform -chdir="$REPO_ROOT/infra" state list 2>/dev/null | grep "module.${key}_platform.helm_release" || true); do
      terraform -chdir="$REPO_ROOT/infra" state rm "$addr" >/dev/null && warn "removed $addr (cluster gone)"
    done
  fi
done
ok "state consistent"

say "A  terraform destroy"
attempt=1
until terraform -chdir="$REPO_ROOT/infra" destroy -input=false -auto-approve -var "image_tag=teardown"; do
  (( attempt >= 2 )) && die "destroy failed twice - see PLAYBOOK > Teardown troubleshooting"
  warn "destroy failed; dropping Helm releases from state and retrying once"
  for addr in $(terraform -chdir="$REPO_ROOT/infra" state list | grep 'helm_release' || true); do
    terraform -chdir="$REPO_ROOT/infra" state rm "$addr" >/dev/null
  done
  attempt=$((attempt + 1))
done
ok "destroyed"

say "I  Inspect leftovers"
result="CLEAN"
if ! "$REPO_ROOT/scripts/leftovers.sh"; then
  result="LEFTOVERS FOUND"
fi

say "N  Notify"
topic=$(aws sns list-topics --region ap-southeast-2 --query "Topics[?ends_with(TopicArn, ':tflab-ops')].TopicArn" --output text)
if [[ -n "$topic" ]]; then
  aws sns publish --region ap-southeast-2 --topic-arn "$topic" \
    --subject "tflab-aws teardown: $result" \
    --message "Teardown finished at $(date -u '+%Y-%m-%d %H:%M UTC') - result: $result. Run scripts/leftovers.sh for detail." >/dev/null
  ok "notified ($result)"
fi
[[ "$result" == "CLEAN" ]] || exit 1
