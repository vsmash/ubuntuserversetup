# serversetup

Tooling and hardening scripts for provisioning an **Ubuntu** server (staging or
production). It installs deploy automation, Slack notifications, the `devlog`
time-logger, Certbot (Cloudflare DNS), and applies firewall/SSH hardening.

> **What this does NOT do:** it does not install a web server, PHP-FPM, or a
> database, and it does not create the deploy user. It assumes a base Ubuntu
> system with the `ubuntu` user already present (see Prerequisites). It sets up
> *tooling* on top of that — it is not a full LAMP/LEMP installer.

---

## TL;DR

```bash
# As root, on the target server:
sudo ./starthere.sh          # interactive menu
sudo ./starthere.sh --all    # run every module in order (prompts before lockdown)
```

- **Must run as root** (`starthere.sh` exits otherwise).
- The **`ubuntu` user must already exist** before running the tooling modules.
- The installer is **`starthere.sh`**. `deployserversetup.sh` is unrelated — it
  is a *git* helper that merges `develop → staging → main` and pushes; do not
  run it on the server.

---

## Prerequisites

| # | Requirement | Why / which module | Provided by this repo? |
|---|---|---|---|
| 1 | **Ubuntu** with `apt`, `systemd` | everything (`apt-get`, `systemctl`, `ufw`, `snap`) | OS |
| 2 | **Run as root / sudo** | `starthere.sh` hard-checks uid 0 | — |
| 3 | **`ubuntu` user exists** (or whatever you set `APP_USER` to) | deploy tooling, devlog, site management all `chown`/`sudo -u`/`crontab -u` against it | Installer **offers to create it** (options 3/5/8/full) |
| 4 | SSH **key** access working for your user | before SSH lockdown (option 7) — otherwise you lock yourself out | — |
| 5 | **PHP + Composer** | devlog → Google Sheets logging (`composer install` runs as `ubuntu`) | **No** |
| 6 | **`ufw`** | firewall lockdown (option 4) | Installer **offers to install it**; you confirm before it's enabled |
| 7 | **Web server** providing `www-data` + a real webroot | site deploys (`deploythis.sh` chowns to `ubuntu:www-data`) | **No** |
| 8 | Google **service-account JSON** | devlog Google Sheets logging | copy manually |
| 9 | **Cloudflare API token** | Certbot DNS validation and/or per-site cache purge | template only |

Certbot's own dependency (`snapd`) **is** installed automatically by the certbot
module.

### Creating the deploy user (the missing step)

On standard Ubuntu **cloud images** (AWS, most VPS providers) the `ubuntu` user
already exists. On a bare/minimal install it does not — the installer now
detects this and **offers to create the user** (with sudo + an `.ssh` dir) when
you run option 3, 5, 8, or the full setup. To create it manually instead:

```bash
adduser --disabled-password --gecos "" ubuntu
usermod -aG sudo ubuntu
# give it your SSH key so you can log in as ubuntu:
install -d -m 700 -o ubuntu -g ubuntu /home/ubuntu/.ssh
# ...add your public key to /home/ubuntu/.ssh/authorized_keys, owned by ubuntu...
```

If you use a different username, set `APP_USER` accordingly in `/etc/app.env`
(step 3 of the menu); every module honours `APP_USER` and defaults to `ubuntu`.

---

## Getting the repo onto the server

```bash
sudo git clone <this-repo-url> /opt/serversetup   # or clone anywhere and run from there
cd /opt/serversetup
sudo ./starthere.sh
```

The tooling modules copy/rsync the working tree to **`/opt/serversetup`** and run
everything from there, symlinking commands into `/usr/local/bin` and
`/usr/local/sbin`. Running the installer directly from `/opt/serversetup` keeps
the source and the installed copy in one place.

---

## The menu (`starthere.sh`)

| Option | Module | Notes |
|---|---|---|
| 1 | Run full setup (all modules) | prompts before the firewall/SSH lockdown steps |
| 2 | System update & essential packages | `apt update`/`upgrade` (prompted) + core tools |
| 3 | Setup environment (`/etc/app.env`) | interactive; populated from `app.env.example` |
| 4 | **Firewall lockdown (SYSOP_IP)** ⚠ | resets UFW to allow *only* `SYSOP_IP` |
| 5 | Deploy tooling (sub-menu) | slack, deploy scripts, devlog, sessionlog, root scripts |
| 6 | Certbot + Cloudflare DNS | installs snapd + certbot + cloudflare plugin |
| 7 | **SSH lockdown (key auth only)** ⚠ | sets `PasswordAuthentication no` |
| 8 | Manage site deployments | add/edit/remove sites + cron-based polling |

### ⚠️ Lock-out risks

Two options can cut off your own access — do them **last**, and only after you've
confirmed key-based SSH works:

- **Option 4 (firewall):** `ufw --force reset` then allow only `SYSOP_IP`. If
  `SYSOP_IP` is wrong/blank, or you connect from a different IP, you're locked
  out. (`SYSOP_IP` must be a valid IPv4 or the step is skipped; if ufw is
  inactive the installer prompts before enabling it.)
- **Option 7 (SSH):** disables password auth. Without a working SSH key you
  cannot get back in.

---

## Recommended order for a fresh staging server

1. Create / confirm the `ubuntu` user **and that you can SSH in as it with a key**.
2. `sudo ./starthere.sh` → **2** — system update & essentials.
3. → **3** — write `/etc/app.env`. Set at minimum `APP_USER`, `SYSOP_IP`, and the
   devlog/Slack values you want.
4. → **6** — Certbot (if you'll terminate TLS here). Edit
   `/etc/letsencrypt/cloudflare.ini` with your real token afterwards.
5. → **5** — deploy tooling. (Install PHP + Composer first if you want devlog's
   Google Sheets logging to work.)
6. → **8** — add your site(s) and enable polling.
7. **Last:** → **4** (firewall) and → **7** (SSH lockdown), after verifying key login.

Prefer the menu over `--all` on a server you care about, so you control the
dangerous steps individually.

---

## Configuration files

### `/etc/app.env` (from [app.env.example](app.env.example))

Created by menu option 3. Sourced by the firewall module and the deploy/devlog
tooling. Key fields:

- `APP_USER` — the non-root deploy user (default `ubuntu`).
- `SYSOP_IP` — the single IP the firewall lockdown will allow. Blank/invalid =
  firewall step is skipped (with a warning).
- `APP_SLACK_*` — Slack webhooks/identity for boot + deploy notifications.
- `DEVLOG_CLIENT` / `DEVLOG_SUBCLIENT` / `DEVLOG_PROJECT` — devlog identity.
- `googleserviceaccount` / `logfilegooglespreadsheetid` — devlog Google Sheets.

### Per-site deploy config — `/etc/deployments/<site>.conf` (from [site.conf.example](site.conf.example))

Created/edited by menu option 8. Drives `deploythis.sh` / `deploy_poll.sh`:
`REPO`, `BRANCH`, `WEBROOT`, `BASE_URL`, and optional Cloudflare cache-purge
(`CLOUDFLARE_ZONE_ID`, `CLOUDFLARE_API_TOKEN`, `PURGE_ON_DEPLOY`).

### `/etc/letsencrypt/cloudflare.ini` (from [cloudflare.ini.example](cloudflare.ini.example))

Cloudflare API token for Certbot DNS validation. The certbot module copies the
template here (chmod 600) — **edit it with your real token**.

---

## How deploys work

`manage_sites` (option 8) writes a site config and an optional **every-minute
cron** (run as `APP_USER`) that calls `deploy_poll.sh <site>`. On a new commit on
the configured branch, [deployments/deploythis.sh](deployments/deploythis.sh):

1. `git fetch` + `git reset --hard origin/<branch>` in `REPO` (as `APP_USER`),
2. runs the **target repo's own** `.scripts/deploy-main.sh <WEBROOT>` if present
   (this repo does not sync files itself),
3. fixes ownership (`ubuntu:www-data`) and perms,
4. runs the target repo's `.scripts/test-production.sh` if present,
5. records last-good commit, optionally purges Cloudflare, notifies Slack.

Failed deploys auto-roll-back to the last-good commit. Manual use:

```bash
sudo /usr/local/sbin/deploythis.sh <site> deploy
sudo /usr/local/sbin/deploythis.sh <site> rollback
```

---

## Related docs

- [DEVLOG_SETUP.md](DEVLOG_SETUP.md) — full devlog (time-logging → Google Sheets) setup.
