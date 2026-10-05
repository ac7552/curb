# Deploying Curb

Curb runs on one DigitalOcean droplet at a fixed monthly price, with Cloudflare's free plan in front.
[Kamal](https://kamal-deploy.org) builds the app into a Docker image on your Mac, sends it to the droplet over
SSH, and runs it next to a Postgres container.

```
visitor ──HTTPS──▶ Cloudflare (free: caching, bot blocking) ──HTTPS──▶ droplet: kamal-proxy ──▶ Rails + Postgres
```

**Cost: $28.80 a month** ($24 droplet + $4.80 weekly backups). Only outgoing traffic past the plan's allowance
(about 4 TB) costs more, at about 1¢ per GB. Cloudflare serves the cached files and turns away junk traffic, so
that isn't a realistic risk. Car photos load from Wikimedia, not the droplet.

## 1. DigitalOcean (about 15 minutes)

1. Sign up at digitalocean.com and add a card. Under **Billing → Billing alerts**, set an alert at $35.
2. Add your Mac's SSH key: run `pbcopy < ~/.ssh/id_ed25519.pub`, then **Settings → Security → SSH Keys → Add
   SSH Key** and paste.
3. **Create → Droplets**:
   - Region: nearest your users (New York or San Francisco).
   - Image: **Ubuntu 24.04 (LTS) x64**.
   - Size: Basic → Regular → **$24/mo** (4 GB memory, 2 CPUs, 80 GB disk). The copied database is about
     23 GB. Resizing up later takes a few minutes from the dashboard.
   - Authentication: **SSH Key** (the one you added). No password.
   - Backups: **weekly**. Monitoring: on (free). Hostname: `curb`.
4. Copy the droplet's **IPv4 address**.
5. **Networking → Firewalls → Create Firewall**: allow incoming **SSH (22), HTTP (80) and HTTPS (443)**, and
   apply it to the droplet. Postgres only listens inside the droplet, so it needs no rule.

## 2. Cloudflare (about 15 minutes)

1. Sign up at cloudflare.com, **Add a site**, enter your domain and pick the **Free** plan.
2. At your domain registrar, replace the nameservers with the two Cloudflare shows you. Cloudflare emails you when
   the domain is active (minutes to a few hours).
3. **DNS → Records**: add an **A** record, name `@`, IPv4 address = the droplet's IP, proxy status **Proxied**
   (orange cloud). Add a second one named `www` if you want `www.` to work too.
4. **SSL/TLS → Overview**: set the mode to **Full (strict)**.
5. **SSL/TLS → Origin Server → Create Certificate**: keep the defaults (RSA, your domain and `*.yourdomain`, 15
   years). Cloudflare shows the certificate and private key **once**. Save them outside the repo:

   ```bash
   mkdir -p ~/.config/curb && chmod 700 ~/.config/curb
   pbpaste > ~/.config/curb/cloudflare-origin.pem       # after copying "Origin Certificate"
   pbpaste > ~/.config/curb/cloudflare-origin-key.pem   # after copying "Private Key"
   chmod 600 ~/.config/curb/*.pem
   ```

   Keep a copy of both in your password manager. Kamal reads them through `.kamal/secrets` on every deploy.
6. **SSL/TLS → Edge Certificates**: turn on **Always Use HTTPS**.

Leave **Bot Fight Mode** off: it challenges automated requests, and Stripe's webhooks are automated.

## 3. First deploy

Open Docker Desktop on your Mac and make sure there's about 10 GB free (the data copy writes a temporary file to
`tmp/`). Kamal builds from the last commit, so commit before deploying.

```bash
export CURB_SERVER=203.0.113.10          # the droplet's IP
export CURB_HOST=curb.example.com        # your domain
export CURB_DATABASE_PASSWORD=$(openssl rand -hex 24)   # save this in your password manager

bin/kamal setup                # installs Docker on the droplet, starts Postgres, builds and starts the app
bin/copy-data-to-server        # copies the data tables from your development database
```

The first build takes 10–20 minutes, since your Mac builds for the droplet's x86 chip. `bin/kamal setup` creates
empty databases. `bin/copy-data-to-server` then fills them with the tables reports read: MOT inspections and rates,
recalls, bulletins, maintenance guides and labor rates. Accounts, saved reports and plan usage are never part of
the copy. Your Mac's demo login never reaches the live site, and running the copy again later never touches real
users or their reports.

The site works on the Free plan straight away. Payments switch on once Stripe is set up (docs/billing.md), with
its webhook at `https://<your domain>/stripe/webhook`.

## After that

```bash
bin/kamal deploy           # ship the latest commit
bin/kamal logs             # follow the app's logs
bin/kamal console          # a Rails console on the server
bin/copy-data-to-server    # after importing MOT files or reading guides locally (deploy first)
```

Maintenance guides are read on your Mac (`bin/rails curb:guides:prefill`), not on the server. Copy the data over
afterwards.

The app trusts Cloudflare's addresses so it sees each visitor's real address (for per-person rate limits). The list
is in `config/environments/production.rb`. Cloudflare rarely changes it, but check https://www.cloudflare.com/ips
once a year.

## Backups

DigitalOcean's weekly backups copy the whole droplet. The database lives in `/root/curb-db/data` on it. For a copy
you keep yourself:

```bash
ssh root@$CURB_SERVER "docker exec curb-db pg_dump -U curb -Fc curb_app_production" > curb-backup.dump
```
