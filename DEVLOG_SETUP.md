# Devlog Setup for Ubuntu Server

This guide sets up the simplified devlog system on your Ubuntu server with Google Sheets integration.

## Features

- **Fixed values**: Client=TMPDesign, Subclient=SMWS, Project=VPS Devops
- **Simple usage**: `devlog "message" [minutes] [ticket]`
- **Auto-calculates time** between log entries
- **Logs to Google Sheets** with full history tracking
- **Works for both root and ubuntu users** with proper permissions

## Installation

### 1. Run deploy_tooling module

Devlog is automatically installed as part of the deploy_tooling setup:

```bash
cd /root/ubuntusersetup
source modules/deploy_tooling.sh
deploy_tooling
```

This will:
- Copy repo to `/opt/serversetup/`
- Symlink `devlog_server.sh` -> `/usr/local/bin/devlog`
- Install Google API PHP client via Composer (as ubuntu user)

### 2. Copy your Google Service Account credentials

From your local machine:

```bash
scp /path/to/your/service-account.json ubuntu@your-server:/tmp/
ssh ubuntu@your-server "sudo mv /tmp/service-account.json /etc/serversetup/credentials/ && sudo chmod 600 /etc/serversetup/credentials/service-account.json"
```

Or copy directly as root:

```bash
scp service-account.json root@server:/etc/serversetup/credentials/
ssh root@server "chmod 600 /etc/serversetup/credentials/service-account.json"
```

### 3. Configure environment for both ubuntu and root users

Add to `/home/ubuntu/.bashrc`:

```bash
# Devlog configuration
export devlogging=true
export logingooglespreadsheet=true
export googleserviceaccount="/etc/serversetup/credentials/service-account.json"
export logfilegooglespreadsheetid="YOUR_GOOGLE_SPREADSHEET_ID"
export bbb="/opt/serversetup"
```

**Also add to `/root/.bashrc`** for when running as root:

```bash
# Devlog configuration
export devlogging=true
export logingooglespreadsheet=true
export googleserviceaccount="/etc/serversetup/credentials/service-account.json"
export logfilegooglespreadsheetid="YOUR_GOOGLE_SPREADSHEET_ID"
export bbb="/opt/serversetup"
```

Note: You don't need to source the devlog script - it's available as `/usr/local/bin/devlog` in your PATH.

Replace `YOUR_GOOGLE_SPREADSHEET_ID` with your actual spreadsheet ID.

### 4. Reload the shell

```bash
# As ubuntu
source ~/.bashrc

# As root
sudo su
source ~/.bashrc
```

## Usage

### Basic logging

```bash
# Full syntax
devlog "Fixed deployment polling" 30 "TMPDES-300"

# Auto-calculate minutes (uses time since last entry)
devlog "Configured nginx" "" "TMPDES-301"

# Use defaults (ticket from git branch or "devops")
devlog "Quick fix" 15

# Minimal (auto-calculate time, auto-detect ticket)
devlog "Updated configs"
```

### Silent mode

No prompts, uses all defaults:

```bash
devlog -s "Background task completed"
```

### Continuation mode

Reuses previous ticket and auto-calculates time:

```bash
devlog "Started work" 0 "TMPDES-300"
devlog -c "Still working on it"
devlog -c "Almost done"
devlog -c "Finished"
```

## Arguments

1. **Message** (required) - What you did
2. **Minutes** (optional) - Time spent
   - Number: Exact minutes
   - Empty or `?`: Auto-calculate from last entry
3. **Ticket** (optional) - Jira ticket number
   - Auto-detects from git branch name
   - Defaults to "devops" if not found

## Fixed Values

These are hardcoded in the server version:

- **Client**: TMPDesign
- **Subclient**: SMWS  
- **Project**: VPS Devops
- **Timezone**: Australia/Sydney

## Files

- `/usr/local/bin/devlog` - Symlink to devlog script (in your PATH)
- `/opt/serversetup/devlog_server.sh` - Main bash script
- `/opt/serversetup/php_functions/` - PHP functions and dependencies
- `/etc/serversetup/credentials/` - Google service account JSON (outside repo)
- `/var/log/devlog.log` - Optional local log file

## Troubleshooting

### Test Google Sheets connection

```bash
php /opt/serversetup/php_functions/logToGoogleSpreadSheet.php \
  "/etc/serversetup/credentials/service-account.json" \
  "YOUR_SPREADSHEET_ID" \
  "TMPDesign" "SMWS" "$(hostname)" "VPS Devops" "TEST-123" "5" "Test entry"
```

### Check PHP dependencies

```bash
cd /opt/serversetup/php_functions
composer show
```

Should show `google/apiclient` installed.

### Enable debug output

Temporarily add to devlog function calls:

```bash
set -x
devlog "test message"
set +x
```

## Google Sheets Format

The script creates/uses a sheet called "RawLog" with columns:

1. Date
2. Time
3. Client
4. Sub Client
5. Host Machine
6. Project
7. Ticket
8. Minutes Spent
9. Log Entry
