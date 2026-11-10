#!/usr/bin/env bash
# Ubuntu 24.04 amd64; run with sudo. Supply role app or ci.
set -euo pipefail
role=${1:?app or ci}; [[ "$role" == app || "$role" == ci ]]
[[ $(uname -m) == x86_64 ]]
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl gnupg git python3 python3-venv unzip jq openssh-server docker.io docker-compose-v2
systemctl enable --now docker
usermod -aG docker ubuntu
# Docker group grants host-level privileges. Only trusted lab administrators/agents.
if [[ "$role" == app ]]; then
  : "${KIND_VERSION:?Set a reviewed kind version, e.g. v0.33.0}"
  : "${KUBECTL_VERSION:?Set a kubectl version compatible with the selected kind node}"
  work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
  curl -fL "https://kind.sigs.k8s.io/dl/$KIND_VERSION/kind-linux-amd64" -o "$work/kind"
  curl -fL "https://kind.sigs.k8s.io/dl/$KIND_VERSION/kind-linux-amd64.sha256sum" -o "$work/kind.sha256"
  (cd "$work"; sed 's/kind-linux-amd64/kind/' kind.sha256 | sha256sum -c -)
  install -m 755 "$work/kind" /usr/local/bin/kind
  curl -fL "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl" -o "$work/kubectl"
  curl -fL "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl.sha256" -o "$work/kubectl.sha256"
  (cd "$work"; printf '%s  kubectl\n' "$(cat kubectl.sha256)" | sha256sum -c -)
  install -m 755 "$work/kubectl" /usr/local/bin/kubectl
  id deploy >/dev/null 2>&1 || useradd --create-home --shell /bin/bash deploy
  apt-get install -y awscli
else
  apt-get install -y fontconfig openjdk-21-jre
  install -m 755 -d /etc/apt/keyrings
  curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key -o /etc/apt/keyrings/jenkins-keyring.asc
  echo 'deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/' > /etc/apt/sources.list.d/jenkins.list
  apt-get update
  : "${JENKINS_VERSION:?Set an available, reviewed Jenkins LTS package version}"
  apt-get install -y "jenkins=$JENKINS_VERSION"
  apt-mark hold jenkins
  systemctl enable --now jenkins
  id buildagent >/dev/null 2>&1 || useradd --create-home --shell /bin/bash buildagent
  usermod -aG docker buildagent
fi
echo 'Bootstrap done. Reconnect SSH to refresh group membership.'
