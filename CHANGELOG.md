## 0.0.4
29 May 2026

- Marked scripts executable in git.
	Prevents git pull from resetting executable permissions set at install time. Covers slack, slack_boot, devlog_server, deploy{,_poll}this, apt_upgrade, root/bash db scripts.
- Refactored deployment sync logic in deploy_tooling.sh
	Handled scenario where source was already at the install location.
	Improved rsync operation to prevent unnecessary syncing.
	Ensured proper removal of leftover staging directories.
- Added initial VERSION file
- Refactored deploy_tooling.sh for clarity and functionality
		Improved directory sync logic and removed redundant checks
		Corrected paths to read from source clone instead of the repo
		Cleaned up leftover directories after sync
- Updated user creation script for enhanced group management
		Added conditional group assignment for users based on presence of www-data
		Improved user creation feedback messages
		Clarified SSH public key instructions and sudo password notes
- Validated SYSOP_IP and added deploy-user preflight
		Fixed firewall placeholder check and offered UFW install
		Ensured app user across setup/tooling/sites
		Loaded app.env in manage sites option
		Fixed stale devlog path and added README
- Refactored session log flushing process
		Improved handling of trivial session detection
		Streamlined command summaries and logging process
		Added timeout protection for AI API calls
- Enhanced session log flushing functionality
		Improved handling for empty session files
		Optimized file handling for session logging
- Added AI summarization feature to session log
		Enabled AI summarization in session log
		Added functions to control AI summarization
		Ensured fallback to raw command logs when AI is disabled
		Improved help messages with examples and function aliases
- Added interactive APT upgrade script and modified devlog installation
		Added interactive APT upgrade functionality with devlog integration
		Ensured devlog_server.sh is executable by all users
		Created new script for handling package upgrades in a user-friendly manner
- Updated deployment script to include app environment loading
		Improved deployment flow in starthere.sh
- Enhanced SSH client IP handling in devlog server script
		Included SSH client IP in computer name if available
		Reorganized IP retrieval logic with fallback to 'who am i'
- Improved deployment and system update scripts
		Changed permissions to 755 for credentials directory
		Added user confirmation prompts for system update and upgrade
		Introduced optional package installation with user confirmation
		Added warnings about potential conflicts during updates
- Improved script permission handling and firewall lockdown logic
		Ensured all users can read and execute scripts in deploy_tooling
		Modified SYSOP_IP validation to allow skipping lockdown gracefully
- Refactored setup_env script for improved environment variable handling
		Cleared output file before writing environment variables
		Corrected regex for key-value parsing
		Handled both single and double quotes in value stripping
		Avoided stdin conflict by reading from /dev/tty for user input
		Streamlined handling of empty lines and comments
- Refactored session log script for cleaner output
		Commented out start and flush messages for cleaner execution
		Removed unnecessary disown commands and cleaned up temp files
- Enhanced session logging and configuration setup
		Added interactive setup for session log configuration
		Improved compatibility with zsh for command capturing
		Implemented safe flushing of session log to avoid race conditions
- Updated deployment scripts and configuration examples
		Updated deploy_poll.sh to change working directory to /tmp
		Modified git remote command to include repo path
		Improved prompts for user input with clear instructions
		Trimmed trailing slashes from user input for repo and webroot
		Revised site.conf.example with path updates for REPO and WEBROOT
- Updated deployment scripts and configuration permissions
		Changed file permissions to 640 and updated ownership to root:ubuntu
		Added ownership change for state directory to ubuntu:ubuntu
- Improved deployment script with error handling
		Changed test script execution to use 'source' for environment variables
		Added 'set -e' to ensure script exits on error in deploy and rollback functions
- Added deployment script for staging and production
		Implemented deployserversetup.sh script
		Included merge prompts between develop and staging
		Automated production deployment process
- Updated environment configuration and scripts
		Added MAIASS_GITKEEP variable to .env.maiass
		Included maiass.log in .gitignore
		Improved repo update logic with rsync
		Added check to prevent unnecessary UFW resets
		Ensured SSH service reload only on config changes
		Revamped full setup process and added interactive menu
