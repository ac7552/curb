# Deploying Curb

Curb runs on one rented server at a fixed monthly price. [Kamal](https://kamal-deploy.org) builds the app into a
Docker image on your Mac, sends it to the server over SSH, and runs it next to a Postgres container. kamal-proxy
handles HTTPS with a free Let's Encrypt certificate.

## What you need

- **A server.** Use Ubuntu with **8 GB of memory and 80 GB of disk**, such as a Hetzner Cloud shared-vCPU plan.
  The copied database is about 23 GB, and rebuilding the rate tables needs room on top of that. Add your SSH key
  when you create the server. Set a billing alert in the provider's console.
- **A domain.** Point its DNS A record at the server's IP address.
- **Docker Desktop**, running on your Mac.
- **At least one git commit.** Kamal builds from the last commit, not from uncommitted files.

## First deploy

```bash
export CURB_SERVER=203.0.113.10          # your server's IP
export CURB_HOST=curb.example.com        # your domain
export CURB_DATABASE_PASSWORD=$(openssl rand -hex 24)   # save this in your password manager

bin/kamal setup                # installs Docker on the server, starts Postgres, builds and starts the app
bin/copy-data-to-server        # copies the data tables from your development database
```

`bin/kamal setup` creates empty databases. `bin/copy-data-to-server` then fills them with the tables reports read.
That includes MOT inspections and rates, recalls, bulletins, maintenance guides and labor rates. Accounts and saved
reports are never part of the copy. Your Mac's demo login never reaches the live site, and running the copy again
later never touches real users or their reports.

## After that

```bash
bin/kamal deploy           # ship the latest commit
bin/kamal logs             # follow the app's logs
bin/kamal console          # a Rails console on the server
bin/copy-data-to-server    # after importing MOT files or reading guides locally (deploy first)
```

Maintenance guides are read on your Mac (`bin/rails curb:guides:prefill`), not on the server. Copy the data over
afterwards.

## Backups

The database lives in `/root/curb-db/data` on the server. Turn on the provider's automatic server backups (usually
about 20% of the server price), or copy a dump off the server now and then:

```bash
ssh root@$CURB_SERVER "docker exec curb-db pg_dump -U curb -Fc curb_app_production" > curb-backup.dump
```
