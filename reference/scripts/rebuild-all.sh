#!/usr/bin/env bash
set -euo pipefail
SCRIPT_START_EPOCH=$(date +%s)
SCRIPT_START_TIME=$(date +"%H:%M:%S")

log_step() { echo -e "\n\033[1;36m============================================================\n[STEP] $1\n============================================================\033[0m"; }
log_info() { echo -e "\033[1;32m[INFO]\033[0m $1"; }


log_step "1/6: Gathering user inputs & detecting Admin IP"
# 1. Gather inputs and detect current Admin IP
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ADMIN_IP="$(curl -4 -fsSL https://icanhazip.com | tr -d "[:space:]")"
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519.pub"

[ -f "${HOME}/.helpdesk-secrets.env" ] && source "${HOME}/.helpdesk-secrets.env"
[ -z "${TFSTATE_BUCKET:-}" ] && read -rp "Enter Terraform state S3 bucket: " TFSTATE_BUCKET
[ -z "${BUDGET_EMAIL:-}" ] && read -rp "Enter AWS Budget email: " BUDGET_EMAIL
[ -z "${SMTP_PASS:-}" ] && { read -rsp "Enter 16-char Google App Password: " SMTP_PASS && echo ""; }
[ -z "${JENKINS_ADMIN_PASSWORD:-}" ] && { read -rsp "Enter new Jenkins Admin password: " JENKINS_ADMIN_PASSWORD && echo ""; }
[ -z "${GRAFANA_ADMIN_PASSWORD:-}" ] && { read -rsp "Enter new Grafana Admin password: " GRAFANA_ADMIN_PASSWORD && echo ""; }
[ -z "${GITHUB_PAT:-}" ] && { read -rsp "Enter GitHub Personal Access Token (PAT): " GITHUB_PAT && echo ""; }

# Ensure Terraform remote state S3 bucket exists
if ! aws s3api head-bucket --bucket "${TFSTATE_BUCKET}" >/dev/null 2>&1; then
  echo "[INFO] State bucket not found. Running Terraform bootstrap..."
  cd "${REPO_ROOT}/reference/terraform/bootstrap"
  terraform init && terraform apply -auto-approve -var="state_bucket=${TFSTATE_BUCKET}" -var="region=us-east-1"
fi

# Clean up leftover global/named resources if they exist outside current state
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ec2 delete-key-pair --region us-east-1 --key-name rt-helpdesk >/dev/null 2>&1 || true
aws budgets delete-budget --account-id "${ACCOUNT_ID}" --budget-name rt-helpdesk-monthly-account-budget >/dev/null 2>&1 || true

log_step "2/6: Provisioning AWS Infrastructure via Terraform"
cd "${REPO_ROOT}/reference/terraform/lab"
cat << HCL > backend.hcl
bucket = "${TFSTATE_BUCKET}"
key = "lab/terraform.tfstate"
region = "us-east-1"
encrypt = true
use_lockfile = true
HCL
terraform init -reconfigure -backend-config=backend.hcl && terraform apply -auto-approve \
  -var="admin_cidr=${ADMIN_IP}/32" -var="ssh_public_key=$(cat "${SSH_KEY_PATH}")" -var="budget_email=${BUDGET_EMAIL}"

log_step "3/6: Retrieving EC2 IPs & waiting for SSH availability"
# 2. Retrieve new EC2 Public IPs from Terraform outputs and wait for SSH
APP_IP=$(terraform output -raw app_public_ip 2>/dev/null || aws ec2 describe-instances --region us-east-1 \
  --filters "Name=tag:Name,Values=*rt-helpdesk*app*" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

CI_IP=$(terraform output -raw ci_public_ip 2>/dev/null || aws ec2 describe-instances --region us-east-1 \
  --filters "Name=tag:Name,Values=*rt-helpdesk*ci*" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

echo "[INFO] App IP: ${APP_IP} | CI IP: ${CI_IP}"

for IP in "${APP_IP}" "${CI_IP}"; do
  until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@"${IP}" "true" 2>/dev/null; do
    sleep 5
  done
done

log_step "4/6: Installing Docker, Kind & Kubectl on App Server"
# 3. Bootstrap App Server (Docker + Kind cluster exposed on internal VPC network)
ssh -o StrictHostKeyChecking=no ubuntu@"${APP_IP}" "
  sudo mkdir -p /opt/rt-helpdesk && sudo chown -R ubuntu:ubuntu /opt/rt-helpdesk
  while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 3; done
  sudo apt-get update && sudo apt-get install -y docker.io curl jq postgresql-client unzip
  sudo usermod -aG docker ubuntu
  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
  curl -LO https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl
"
scp -o StrictHostKeyChecking=no -r "${REPO_ROOT}/app" "${REPO_ROOT}/reference" "${REPO_ROOT}/monitoring" ubuntu@"${APP_IP}":/opt/rt-helpdesk/

ssh -o StrictHostKeyChecking=no ubuntu@"${APP_IP}" "
  cat << 'KINDCFG' > /tmp/kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: \"0.0.0.0\"
  apiServerPort: 6443
KINDCFG
  sg docker -c 'kind get clusters | grep -q "^helpdesk$" || kind create cluster --name helpdesk --config /tmp/kind-config.yaml && mkdir -p ~/.kube && kind get kubeconfig --name helpdesk > ~/.kube/config && cp ~/.kube/config ~/.kube/helpdesk && chmod 600 ~/.kube/helpdesk'
"

log_step "5/6: Deploying Kubernetes App, Monitoring & Alertmanager"
# 4a. Deploy Helpdesk App, Monitoring & Alertmanager
ssh -o StrictHostKeyChecking=no ubuntu@"${APP_IP}" "
  cd /opt/rt-helpdesk && kubectl create namespace helpdesk --dry-run=client -o yaml | kubectl apply -f - && kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
  DB_PASS=\$(openssl rand -hex 16)
  kubectl -n helpdesk create secret generic app-secret --from-literal=SECRET_KEY=\$(openssl rand -hex 32) --from-literal=DB_PASSWORD="\$DB_PASS" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n helpdesk create secret generic db-secret --from-literal=POSTGRES_DB=helpdesk --from-literal=POSTGRES_USER=helpdesk --from-literal=POSTGRES_PASSWORD="\$DB_PASS" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n helpdesk apply -f reference/k8s/app.yaml
  kubectl -n helpdesk wait --for=condition=ready pod/db-0 --timeout=180s
  kubectl -n helpdesk set image deployment/api api=ghcr.io/elirangz1-creator/rt-helpdesk@sha256:fd56d47e38757ab933aecb6f4467bfa52182565596fc123ea0d5e6fed0ebd9bb
  sleep 10
  kubectl -n helpdesk exec deploy/api -- flask --app app init-db || true
  kubectl -n helpdesk rollout status deployment/api --timeout=180s
  kubectl -n helpdesk exec deploy/api -- flask --app app seed-db || true
  kubectl -n helpdesk apply -f reference/k8s/init-db.yaml || true
  kubectl -n monitoring create secret generic alertmanager-smtp --from-literal=smtp_password='${SMTP_PASS}' --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n monitoring create configmap prometheus-config --from-file=prometheus.yml=reference/k8s/prometheus.yml --from-file=alerts.yml=reference/k8s/alerts.yml --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n monitoring create secret generic grafana-secret --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -hex 12)}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f reference/k8s/monitoring.yaml && bash reference/scripts/bootstrap-monitoring.sh && kubectl apply -f reference/k8s/alertmanager.yaml
"

log_step "6/6: Installing Jenkins CI & Configuring JCasC Automation"
# 4b. Install Jenkins, configure buildagent & print initial admin password
ssh -o StrictHostKeyChecking=no ubuntu@"${CI_IP}" "
  sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile && echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
  while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 3; done
  sudo apt-get update && sudo apt-get install -y fontconfig openjdk-21-jre docker.io docker-compose-v2 git
  sudo wget -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
  echo 'deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/' | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
  while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 3; done
  sudo apt-get update && sudo apt-get install -y jenkins && sudo systemctl enable --now jenkins
  sudo useradd -m -s /bin/bash buildagent && sudo usermod -aG docker buildagent
  curl -LO https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl  
  [ -f /var/lib/jenkins/.ssh/id_ed25519 ] || sudo test -f /var/lib/jenkins/.ssh/id_ed25519 || sudo -u jenkins ssh-keygen -t ed25519 -f /var/lib/jenkins/.ssh/id_ed25519 -N ''
  sudo mkdir -p /home/buildagent/.ssh && sudo cp /var/lib/jenkins/.ssh/id_ed25519.pub /home/buildagent/.ssh/authorized_keys
  sudo chown -R buildagent:buildagent /home/buildagent/.ssh && sudo chmod 700 /home/buildagent/.ssh && sudo chmod 600 /home/buildagent/.ssh/authorized_keys
"

JENKINS_PUB=$(ssh -o StrictHostKeyChecking=no ubuntu@"${CI_IP}" "sudo cat /var/lib/jenkins/.ssh/id_ed25519.pub")
ssh -o StrictHostKeyChecking=no ubuntu@"${APP_IP}" "echo '${JENKINS_PUB}' >> ~/.ssh/authorized_keys"

# 5. Configure Jenkins automatically via JCasC (Plugins, Kubeconfig & Secrets)
APP_PRIV_IP=$(aws ec2 describe-instances --region us-east-1 \
  --filters "Name=tag:Name,Values=*rt-helpdesk*app*" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)

KUBECONFIG_B64=$(ssh -o StrictHostKeyChecking=no ubuntu@"${APP_IP}" "cat ~/.kube/config" | sed "s/127.0.0.1:[0-9]*/${APP_PRIV_IP}:6443/g" | base64 | tr -d '\n')

sed -E "s/(value: \")[0-9.]+(\")/\1${APP_PRIV_IP}\2/g" "${REPO_ROOT}/reference/jenkins/jenkins.yaml" > /tmp/jenkins.yaml && scp -o StrictHostKeyChecking=no /tmp/jenkins.yaml ubuntu@"${CI_IP}":/tmp/jenkins.yaml

ssh -o StrictHostKeyChecking=no ubuntu@"${CI_IP}" "
  sudo systemctl stop jenkins
  sudo mkdir -p /var/lib/jenkins/plugins
  sudo wget -q -O /tmp/jenkins-plugin-manager.jar https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.13.2/jenkins-plugin-manager-2.13.2.jar
  sudo java -jar /tmp/jenkins-plugin-manager.jar --war /usr/share/java/jenkins.war --plugin-download-directory /var/lib/jenkins/plugins \
    --plugins configuration-as-code job-dsl ssh-slaves workflow-aggregator git credentials-binding timestamper docker-workflow
  ssh-keyscan -H ${APP_PRIV_IP} | sudo tee /var/lib/jenkins/app_known_hosts > /dev/null && sudo chown jenkins:jenkins /var/lib/jenkins/app_known_hosts
  sudo mv /tmp/jenkins.yaml /var/lib/jenkins/jenkins.yaml
  sudo chown -R jenkins:jenkins /var/lib/jenkins/plugins /var/lib/jenkins/jenkins.yaml

  sudo mkdir -p /etc/systemd/system/jenkins.service.d
  cat << EOF | sudo tee /etc/systemd/system/jenkins.service.d/jcasc.conf > /dev/null
[Service]
Environment=\"JAVA_OPTS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false\"
Environment=\"CASC_JENKINS_CONFIG=/var/lib/jenkins/jenkins.yaml\"
Environment=\"JENKINS_ADMIN_PASSWORD=${JENKINS_ADMIN_PASSWORD}\"
Environment=\"APP_PRIV_IP=${APP_PRIV_IP}\"
Environment=\"GITHUB_PAT=${GITHUB_PAT}\"
Environment=\"KUBECONFIG_BASE64=${KUBECONFIG_B64}\"
EOF

  BUILDAGENT_KEY=\$(sudo cat /var/lib/jenkins/.ssh/id_ed25519 | awk '{printf \"%s\\\\n\", \$0}')
  echo \"Environment=\\\"BUILDAGENT_SSH_KEY=\${BUILDAGENT_KEY}\\\"\" | sudo tee -a /etc/systemd/system/jenkins.service.d/jcasc.conf > /dev/null

  sudo systemctl daemon-reload && sudo systemctl start jenkins
  echo '[SUCCESS] Jenkins is 100% configured and running via JCasC!'
  echo 'Waiting for Jenkins web UI to initialize...'
  for i in {1..45}; do
    curl -sf -u \"admin:${JENKINS_ADMIN_PASSWORD}\" \"http://localhost:8080/api/json\" >/dev/null 2>&1 && break
    sleep 3
  done

  echo \"Verifying APP_HOST (${APP_PRIV_IP}) inside Jenkins configuration...\"
  VERIFIED=0
  for i in {1..15}; do
    if grep -q \"APP_PRIV_IP=${APP_PRIV_IP}\" /etc/systemd/system/jenkins.service.d/jcasc.conf && curl -sf -u \"admin:${JENKINS_ADMIN_PASSWORD}\" \"http://localhost:8080/job/helpdesk-release/api/json\" >/dev/null 2>&1; then
      VERIFIED=1
      break
    fi
    sleep 2
  done

  if [ \"\$VERIFIED\" -eq 1 ]; then
    echo \"[SUCCESS] Jenkins is configured and APP_HOST is verified as ${APP_PRIV_IP}!\"
  else
    echo \"[ERROR] Failed to verify APP_HOST (${APP_PRIV_IP}) in Jenkins configuration.\"
    exit 1
  fi
"

SCRIPT_END_EPOCH=$(date +%s)
SCRIPT_END_TIME=$(date +"%H:%M:%S")
ELAPSED=$((SCRIPT_END_EPOCH - SCRIPT_START_EPOCH))
MINS=$((ELAPSED / 60))
SECS=$((ELAPSED % 60))

echo "=========================================="
echo "[SUCCESS] Infrastructure & CI/CD Setup Complete!"
echo "  App Server Public IP:  ${APP_IP}"
echo "  App Server Private IP: ${APP_PRIV_IP}"
echo "  CI Server Public IP:   ${CI_IP}"
echo "------------------------------------------"
echo "  Start Time:     ${SCRIPT_START_TIME}"
echo "  End Time:       ${SCRIPT_END_TIME}"
echo "  Total Duration: ${MINS}m ${SECS}s (${ELAPSED}s)"
echo "=========================================="
echo "Next steps:"
echo "  1. Run 'helpdesk-tunnel' to open all service tunnels."
echo "  2. Open http://localhost:8080/job/helpdesk-release/ and click 'Build Now'."
echo "  3. Once build completes, access App (8000), Prometheus (9090), and Grafana (3000)."
