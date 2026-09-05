# DevOps Files

A curated collection of production-oriented DevOps assets: AWS IAM policies, web-server configurations, infrastructure-as-code, container images, and automation scripts.

These files are intended as reusable starting points. Review each file, replace placeholders, and adapt values to the target environment before applying anything to production.

---

## Table of Contents

- [Purpose](#purpose)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Directory Reference](#directory-reference)
  - [AWS](#aws)
  - [Apache](#apache)
  - [Nginx](#nginx)
  - [Docker](#docker)
  - [Terraform](#terraform)
  - [Shell Scripts](#shell-scripts)
- [How Configuration Files Are Organized](#how-configuration-files-are-organized)
- [Deployment Workflow](#deployment-workflow)
- [Safety Notes](#safety-notes)
- [Contributing](#contributing)

---

## Purpose

This repository centralizes the configurations and scripts used to:

- Provision and harden Linux servers (users, SSH, disk growth)
- Install and bootstrap local Kubernetes tooling (Docker, kubectl, Minikube, Istio)
- Reverse-proxy Node.js, React, WebSocket, and API workloads with Nginx or Apache
- Apply least-privilege AWS IAM, S3, CloudFront, and MFA policies
- Manage AWS infrastructure with Terraform
- Migrate application data and invalidate CloudFront caches after content changes

It is organized by technology domain so each asset can be copied, customized, and applied independently.

---

## Repository Structure

```text
DevOps-files/
├── AWS/                  AWS IAM policies, S3/CloudFront configs, Lambda, EBS resize
├── Apache/               Apache virtual-host configuration for Laravel
├── Docker/               Custom Ubuntu image for Kubernetes networking practice
├── Nginx/                Reverse-proxy and static-site configurations
├── shell-script/         Installers, user provisioning, EKS upgrade, DB migration
├── terraform/            AWS Security Group (IaC)
└── README.md
```

| Directory        | What it contains                                      | Typical use                          |
| ---------------- | ----------------------------------------------------- | ------------------------------------ |
| `AWS/`           | IAM/S3 JSON policies, Lambda, EBS resize script       | Cloud access control and operations  |
| `Apache/`        | Virtual host `.conf`                                  | Laravel application hosting          |
| `Nginx/`         | Server-block configs (proxy, SPA, CORS, auth)         | Reverse proxy and static frontends   |
| `Docker/`        | Dockerfile with networking tools + Nginx              | Local/K8s network-policy labs        |
| `terraform/`     | AWS Security Group (HCL)                              | Repeatable network baseline          |
| `shell-script/`  | Bash installers and operational automation            | Bootstrap and day-2 operations       |

---

## Prerequisites

Install only what you need for the files you plan to use.

| Area            | Required tools                                                                 |
| --------------- | ------------------------------------------------------------------------------ |
| AWS policies    | AWS account, IAM permissions, AWS CLI (optional but recommended)               |
| Terraform       | [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.3, AWS provider credentials |
| Docker          | Docker Engine or Docker Desktop                                                |
| Kubernetes      | `kubectl`, a reachable cluster (Minikube, Docker Desktop, or EKS)              |
| Istio           | `kubectl`, `curl`, `tar`; cluster admin access                                 |
| Nginx / Apache  | A Linux host with the corresponding web server installed                       |
| Shell scripts   | Bash, and `sudo` where the script mutates the system                           |

Replace every placeholder before apply:

- `YOUR-BUCKET-NAME` / `<YOUR-BUCKET-ARN>`
- `YOUR_AWS_ACCOUNT_ID` / `YOUR_CLOUDFRONT_DIST_ID`
- `<YOUR-LOCAL-NAME>` (Terraform resource name)
- Database endpoints, usernames, and passwords in `Db-migration-script.sh`
- `your_domain` and document-root paths in Nginx/Apache configs

---

## Getting Started

```bash
git clone https://github.com/aaqibShaikh199/DevOps-files.git
cd DevOps-files
```

Most assets are standalone. Copy the relevant file into the target environment, substitute placeholders, then apply it with the matching tool (`aws`, `terraform`, `nginx -t`, `docker build`, or `bash`).

---

## Directory Reference

### AWS

IAM policies, S3 bucket policies, CloudFront access rules, a Lambda function, and an EBS volume-resize script.

| File | Type | Description |
| ---- | ---- | ----------- |
| `IAM-policy-for-specific-bucket-access.json` | IAM identity policy | Grants an IAM user list-all-buckets plus full access to one named bucket. Replace `YOUR-BUCKET-NAME-HERE`. |
| `ec2-access-s3-without-acess-key-and-secret-key.json` | IAM role policy | Attach to an EC2 instance profile so the instance can reach a specific bucket without access keys. |
| `S3-public-policy.json` | S3 bucket policy | Allows public `s3:GetObject` on a bucket. Use only for intentionally public assets. |
| `S3-CORS.json` | S3 CORS configuration | Permits GET/POST/PUT/DELETE/HEAD from any origin. Tighten `AllowedOrigins` in production. |
| `access-private-s3-with-cloudfront` | S3 bucket policy | Keeps the bucket private and allows `GetObject` only from a specific CloudFront distribution (`AWS:SourceArn`). |
| `force-fully-MFA-policy.json` | IAM identity policy | Allows MFA setup and password change; denies all other AWS actions until MFA is present. |
| `lambda-function.py` | AWS Lambda | Triggered when `robots.txt` / `sitemap.xml` (or similar) change in S3. Creates a CloudFront invalidation (`/*`) for every environment variable that starts with `DISTRIBUTION_ID_`. |
| `ebs-volume-increase.sh` | Bash | After an EBS volume is enlarged in the AWS console, grows the partition and filesystem. Supports NVMe (`nvme0n1` / `nvme1n1`) and Xen (`xvda` / `xvdf`) devices for XFS and ext4. |

**Apply an IAM policy (example):**

```bash
aws iam put-user-policy \
  --user-name <iam-user> \
  --policy-name SpecificBucketAccess \
  --policy-document file://AWS/IAM-policy-for-specific-bucket-access.json
```

**Apply an S3 bucket policy (example):**

```bash
aws s3api put-bucket-policy \
  --bucket <bucket-name> \
  --policy file://AWS/access-private-s3-with-cloudfront
```

**Lambda environment variables:**

```text
DISTRIBUTION_ID_PROD=E1234567890ABC
DISTRIBUTION_ID_STAGING=E0987654321XYZ
```

Wire the function to an S3 object-created / object-updated event on the relevant keys.

---

### Apache

| File | Description |
| ---- | ----------- |
| `laravel.conf` | Virtual host on port 80 for a Laravel application. Sets `DocumentRoot` to the project's `public/` directory, enables `.htaccess` overrides, and blocks access to `.ht*`, `.env*`, and `.git` paths. |

**Usage:**

1. Copy the file to `/etc/apache2/sites-available/`.
2. Update `ServerName`, `DocumentRoot`, and the `<Directory>` path.
3. Enable the site and reload Apache:

```bash
sudo a2ensite laravel.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
```

---

### Nginx

Server-block templates for common application topologies. Copy a file into `/etc/nginx/sites-available/`, symlink it into `sites-enabled`, replace `your_domain` and upstream ports, then validate.

```bash
sudo nginx -t && sudo systemctl reload nginx
```

| File | Role | Notes |
| ---- | ---- | ----- |
| `react-nginx.conf` | Static React / SPA host | Serves files from a document root and uses `try_files $uri /index.html` for client-side routing. |
| `node-js-proxy-conf` | Node.js reverse proxy | Proxies HTTP to `localhost:3001` and forwards `Host`, `X-Real-IP`, and `X-Forwarded-For`. |
| `header-socket-connection-conf` | WebSocket-capable proxy | Same upstream as the Node proxy, plus `Upgrade` / `Connection` headers for Socket.IO or similar. |
| `popop` | Authenticated reverse proxy | Proxies to `127.0.0.1:5000` with WebSocket support and HTTP Basic Auth (`auth_basic` + `/etc/nginx/.htpasswd`). Useful for locking Swagger or internal UIs. |
| `cors-error` | CORS header snippet | Adds `Access-Control-Allow-*` headers on a `location /` block. Merge into an existing server block; it is not a complete vhost. |

**Create a Basic Auth password file (for `popop`):**

```bash
sudo htpasswd -c /etc/nginx/.htpasswd <username>
```

The `popop` config expects `map $http_upgrade $connection_upgrade` to be defined in `nginx.conf` (or an included file):

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
```

---

### Docker

| File | Description |
| ---- | ----------- |
| `Dockerfile` | Ubuntu-based image with Nginx and networking utilities (`ping`, `curl`, `dig`, `ip`, `traceroute`, `netcat`, `telnet`). Serves a simple index page on port 80. Built for Kubernetes network-policy practice. |

```bash
cd Docker
docker build -t aaqib-net-tools:latest .
docker run --rm -p 8080:80 aaqib-net-tools:latest
```

In a cluster, deploy the image as a debug or workload pod and attach NetworkPolicies to observe allowed and denied traffic.

---

### Terraform

| File | Description |
| ---- | ----------- |
| `aws-security-group.tf` | Creates an AWS Security Group with inbound HTTP (80) and HTTPS (443) from `0.0.0.0/0`, inbound SSH (22) from a single CIDR, and unrestricted IPv4 egress. |

Before `terraform apply`:

1. Replace `<YOUR-LOCAL-NAME>` in the resource and all rule references with a valid Terraform identifier.
2. Replace the SSH CIDR (`103.249.234.117/32`) with your current public IP or a bastion range.
3. Associate the security group with the intended VPC if you are not using the default VPC.

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

---

### Shell Scripts

Operational automation for host bootstrap, Kubernetes tooling, user management, EKS upgrades, and database migration.

Make a script executable, then run it. Scripts that mutate the system generally require `sudo`.

```bash
chmod +x shell-script/<script>.sh
```

#### Kubernetes and container tooling

| Script | Platform | What it does |
| ------ | -------- | ------------ |
| `Install-Docker.sh` | Ubuntu / Debian | Installs Docker Engine, CLI, containerd, Buildx, and Compose from the official apt repository. Adds the current user to the `docker` group so Docker can be used without `sudo` after a re-login. |
| `kubectl-install.sh` | Linux amd64 | Downloads the latest stable `kubectl`, verifies the SHA-256 checksum, installs it to `/usr/local/bin`, and also registers the Kubernetes apt repository (v1.30). |
| `Install-Minikube-With-Kubectl.sh` | Linux / macOS | Installs `kubectl` and Minikube into `~/.local/bin`, adds that path to the shell, and creates a `k` alias for `kubectl`. Start the cluster yourself with `minikube start`. |
| `install-minikube-in-macbook.sh` | macOS only | Installs Homebrew if needed, ensures Docker Desktop is running, installs Minikube and kubectl via Brew, and starts a cluster (`--cpus`, `--memory`, `--driver` are configurable). |
| `Install-ISTIO-for-Mac&Linux.sh` | macOS (Intel + Apple Silicon) and Linux | Downloads Istio (default `1.30.4`), installs the `demo` profile in sidecar mode, waits for the control plane, and enables automatic sidecar injection on a namespace (default `default`). |

**Istio environment overrides:**

```bash
ISTIO_VERSION=1.30.4 \
ISTIO_PROFILE=demo \
INJECT_NAMESPACE=my-app \
ALLOW_UPGRADE=true \
INSTALL_ISTIOCTL_GLOBALLY=true \
  ./shell-script/Install-ISTIO-for-Mac\&Linux.sh
```

**macOS Minikube example:**

```bash
./shell-script/install-minikube-in-macbook.sh --cpus 4 --memory 8192 --driver docker
```

#### Linux user management

| Script | What it does |
| ------ | ------------ |
| `create-new-user-with-root-permission.sh` | Interactive. Creates a user with a home directory, adds them to `sudo`, and grants passwordless `NOPASSWD:ALL`. Must be run as root. |
| `create-new-user-with-specific-folder-permissio.sh` | Interactive. Creates a user, owns a chosen folder (`chmod 755`), and enables SSH password authentication. |
| `create-new-user-with-read-only-permissio.sh` | Idempotent auditor account. The user can read files (including logs via `adm` / `systemd-journal`) but cannot create, modify, or delete files, has no sudo, and cannot write to world-writable paths such as `/tmp`. Supports `--verify`, `--revert`, `--dry-run`, `--allow-from`, and `--password-stdin`. Designed for Ubuntu 22.04 (AWS EC2 cloud image). |

```bash
sudo ./shell-script/create-new-user-with-read-only-permissio.sh
sudo ./shell-script/create-new-user-with-read-only-permissio.sh --verify
sudo ./shell-script/create-new-user-with-read-only-permissio.sh --revert --delete-user
```

Default auditor username: `securify-user` (override with `USERNAME=`).

#### Cloud operations

| Script | What it does |
| ------ | ------------ |
| `update-aws-eks-cluster.sh` | Interactive EKS upgrade. Validates the cluster and node group, upgrades the control plane, upgrades the node group with `eksctl`, then upgrades the `kube-proxy`, `coredns`, and `vpc-cni` add-ons. Currently targets Kubernetes **1.32**. Requires AWS CLI, `eksctl`, and a named AWS profile. |
| `Db-migration-script.sh` | MySQL → PostgreSQL migration. Tests connections, dumps MySQL data, creates a PostgreSQL schema (ASP.NET Identity plus application tables), and imports via `pgloader` with a CSV fallback. Fill in RDS endpoints and credentials before running. Requires `mysql`, `psql`, and preferably `pgloader`. |

---

## How Configuration Files Are Organized

Assets are grouped by **runtime domain**, not by file extension. Use the domain folder as the source of truth, then apply the file with the matching control plane.

| Format | Location | Applied with | Scope |
| ------ | -------- | ------------ | ----- |
| JSON (IAM / S3 / CORS) | `AWS/` | AWS Console, AWS CLI, or CloudFormation/Terraform wrappers | Identity, bucket access, CDN origin lock-down |
| Nginx server blocks | `Nginx/` | `nginx -t` + `systemctl reload nginx` | HTTP(S) routing, proxy, CORS, Basic Auth |
| Apache virtual hosts | `Apache/` | `a2ensite` + `apache2ctl configtest` | Laravel document root and secret-path denial |
| Terraform HCL | `terraform/` | `terraform plan` / `apply` | Security group ingress/egress |
| Dockerfile | `Docker/` | `docker build` / Kubernetes manifests | Lab and debug workloads |
| Bash | `shell-script/`, `AWS/` | `bash` / `sudo` | Host bootstrap and operational runbooks |
| Python | `AWS/lambda-function.py` | AWS Lambda + S3 event trigger | CloudFront cache invalidation |

There is no single “apply everything” pipeline. Each file is an independent unit so it can be reused across environments without pulling unrelated infrastructure.

**Suggested apply order for a new environment**

1. Identity and network first — IAM policies, MFA, Terraform security group.
2. Host bootstrap — Docker, kubectl/Minikube/Istio, Linux users.
3. Edge and application — Nginx/Apache configs, Docker image, S3/CloudFront policies.
4. Day-2 operations — EBS resize, EKS upgrade, database migration, Lambda invalidation.

---

## Deployment Workflow

```text
Clone repo
    │
    ├─ Cloud access
    │     AWS/*.json  →  IAM / S3 / CloudFront
    │     terraform/  →  Security Group
    │
    ├─ Compute & Kubernetes
    │     Install-Docker.sh
    │     kubectl / Minikube / Istio scripts
    │     Docker/Dockerfile  →  image → cluster
    │
    ├─ Application edge
    │     Nginx/* or Apache/laravel.conf
    │
    └─ Operations
          ebs-volume-increase.sh
          update-aws-eks-cluster.sh
          Db-migration-script.sh
          lambda-function.py
```

Treat this repository as a **source of templates**. Promote a copy into the environment’s own configuration management (Ansible, Terraform modules, GitOps) rather than applying files from this tree directly in production on an ongoing basis.

---

## Safety Notes

- **Placeholders** — Policies and Terraform still contain sample ARNs, bucket names, and a concrete SSH source IP. Applying them unchanged will fail or open the wrong access path.
- **Public S3 and open CORS** — `S3-public-policy.json` and `S3-CORS.json` are intentionally permissive. Restrict principals and origins before using them on real data.
- **Privileged user scripts** — `create-new-user-with-root-permission.sh` grants passwordless sudo. Use only on hosts where that is an accepted risk.
- **SSH password auth** — `create-new-user-with-specific-folder-permissio.sh` enables password authentication globally. Prefer key-based auth and scoped `Match` blocks (as the read-only user script does).
- **EKS upgrades** — Control-plane and node-group upgrades are one-way and can disrupt workloads. Take backups, confirm addon compatibility, and run during a maintenance window.
- **Database migration** — `Db-migration-script.sh` drops and recreates the PostgreSQL `public` schema. Never point it at a database that already holds production data you cannot rebuild.
- **Secrets** — Do not commit real passwords, access keys, or account IDs. The Lambda function and migration script expect secrets from the environment or a secrets manager.

---

## Contributing

When adding a new asset:

1. Place it in the existing domain directory (`AWS`, `Nginx`, `shell-script`, and so on). Create a new top-level directory only for a new technology domain.
2. Use placeholders (`<YOUR-BUCKET-NAME>`, `your_domain`) instead of real account data.
3. Keep scripts idempotent where practical (`set -euo pipefail`, existence checks, `--dry-run` / `--verify` when the change is destructive).
4. Document purpose, required tools, and any environment variables in this README.

---

## License

Personal / team reference repository. Reuse and adapt the files as needed; review every policy and script against your organization’s security baseline before production use.
