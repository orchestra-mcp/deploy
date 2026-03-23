# CI/CD Workflows

## Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `deploy.yml` | Push to `main` or manual | SSH into server, sync files, pull images, restart services |
| `validate.yml` | PR to `main` or config changes | Validate docker-compose, Caddyfile, and run migrations against test DB |

## Required GitHub Secrets

Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Description | How to get it |
|--------|-------------|---------------|
| `DEPLOY_HOST` | Server IP or hostname | Your server's public IP (e.g., `203.0.113.1`) |
| `DEPLOY_USER` | SSH username | Usually `root` or `deploy` |
| `DEPLOY_SSH_KEY` | SSH private key (Ed25519) | See below |
| `DEPLOY_KNOWN_HOSTS` | Server's SSH host key | See below |

### Generate SSH Key for CI/CD

On your **local machine**:

```bash
# Generate a dedicated deploy key (no passphrase)
ssh-keygen -t ed25519 -C "orchestra-deploy" -f ~/.ssh/orchestra_deploy -N ""

# Copy public key to server
ssh-copy-id -i ~/.ssh/orchestra_deploy.pub root@YOUR_SERVER_IP

# Get the private key (paste into DEPLOY_SSH_KEY secret)
cat ~/.ssh/orchestra_deploy

# Get known_hosts entry (paste into DEPLOY_KNOWN_HOSTS secret)
ssh-keyscan YOUR_SERVER_IP
```

### Manual Deploy

You can trigger a deploy manually from the GitHub Actions tab:
1. Go to **Actions → Deploy to Production**
2. Click **Run workflow**
3. Optionally specify a single service to restart (e.g., `supabase-db`)

### Deploy Flow

```
Push to main → GitHub Actions
  → rsync files to server (excludes .env, .git, logs)
  → docker compose pull (update images)
  → docker compose up -d (restart changed services)
  → Health check verification
  → Cleanup old Docker images (>7 days)
```
