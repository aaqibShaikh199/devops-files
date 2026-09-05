# DevOps Files

Reusable configs and scripts for AWS, Kubernetes, web servers, and Linux hosts.

Replace placeholders (`YOUR-BUCKET-NAME`, `your_domain`, credentials) before using anything.

```bash
git clone https://github.com/aaqibShaikh199/DevOps-files.git
cd DevOps-files
```

---

## What's in here

```text
AWS/            IAM, S3, CloudFront, Lambda, EBS resize
Apache/         Laravel virtual host
Nginx/          Reverse proxy and static-site configs
Docker/         Ubuntu image with networking tools (K8s labs)
terraform/      AWS security group
shell-script/   Installers, users, EKS upgrade, DB migration
```

Each file stands alone. Copy what you need, edit it, then apply it.

---

## AWS

| File | What it does |
| ---- | ------------ |
| `IAM-policy-for-specific-bucket-access.json` | IAM user access to one S3 bucket only |
| `ec2-access-s3-without-acess-key-and-secret-key.json` | EC2 role policy — S3 access without access keys |
| `S3-public-policy.json` | Public read on a bucket (use only if you mean it) |
| `S3-CORS.json` | S3 CORS — tighten origins in production |
| `access-private-s3-with-cloudfront` | Private bucket, readable only via CloudFront |
| `force-fully-MFA-policy.json` | Block AWS access until the user enables MFA |
| `lambda-function.py` | Invalidate CloudFront when S3 objects change (`DISTRIBUTION_ID_*` env vars) |
| `ebs-volume-increase.sh` | Grow the disk after you resize an EBS volume |

---

## Nginx & Apache

Copy into `sites-available`, set the domain/path, then reload.

| File | What it does |
| ---- | ------------ |
| `Nginx/react-nginx.conf` | Host a React / SPA app |
| `Nginx/node-js-proxy-conf` | Proxy to a Node app (`localhost:3001`) |
| `Nginx/header-socket-connection-conf` | Same proxy, with WebSocket support |
| `Nginx/popop` | Proxy + Basic Auth (lock Swagger / internal UIs) |
| `Nginx/cors-error` | CORS headers to add to an existing `location` |
| `Apache/laravel.conf` | Laravel vhost — serves `public/`, blocks `.env` and `.git` |

```bash
sudo nginx -t && sudo systemctl reload nginx
sudo apache2ctl configtest && sudo systemctl reload apache2
```

---

## Docker & Terraform

**Docker** — Ubuntu image with Nginx and network tools. Useful for Kubernetes network-policy practice.

```bash
cd Docker && docker build -t net-tools:latest . && docker run --rm -p 8080:80 net-tools:latest
```

**Terraform** — Security group: HTTP/HTTPS open, SSH from one IP. Replace `<YOUR-LOCAL-NAME>` and the SSH CIDR first.

```bash
cd terraform && terraform init && terraform plan && terraform apply
```

---

## Scripts

```bash
chmod +x shell-script/*.sh
```

| Script | What it does |
| ------ | ------------ |
| `Install-Docker.sh` | Install Docker on Ubuntu (no sudo after re-login) |
| `kubectl-install.sh` | Install kubectl on Linux |
| `Install-Minikube-With-Kubectl.sh` | Install Minikube + kubectl, add `k` alias |
| `install-minikube-in-macbook.sh` | macOS: Docker Desktop + Minikube + start cluster |
| `Install-ISTIO-for-Mac&Linux.sh` | Install Istio (demo profile) on Mac or Linux |
| `create-new-user-with-root-permission.sh` | New user with passwordless sudo |
| `create-new-user-with-specific-folder-permissio.sh` | New user with access to one folder |
| `create-new-user-with-read-only-permissio.sh` | Auditor user — can read, cannot write |
| `update-aws-eks-cluster.sh` | Upgrade an EKS cluster to 1.32 |
| `Db-migration-script.sh` | Migrate MySQL → PostgreSQL |

---

## Before you apply

- Fill in bucket names, domains, IPs, and credentials.
- `S3-public-policy.json` and open CORS are not safe for private data.
- Root-user and EKS-upgrade scripts are destructive — review them first.
- `Db-migration-script.sh` drops the Postgres `public` schema. Do not run it on a live database you cannot rebuild.
