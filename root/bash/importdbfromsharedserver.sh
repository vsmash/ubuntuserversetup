#!/usr/bin/env bash

source /etc/app.env

FULL_OUT="db-full-$(date +%Y%m%d%H%M%S).sql"
localdbname="${LOCAL_DB_NAME}"
localdbuser="${LOCAL_DB_USER}"
# make sure ~/tmp exists
mkdir -p ~/tmp
source ~/.db_password

devlog -s "DB import from shared server started"

if ! ssh "${SHARED_SERVER_ALIAS}" "
  set -e
  site_path=\"${SHARED_SITE_PATH}\"
    db_host=\$(grep DB_HOST \"\$site_path/wp-config.php\" | cut -d \' -f 4) 
    db_name=\$(grep DB_NAME \"\$site_path/wp-config.local.php\" | cut -d \' -f 4)
    db_user=\$(grep DB_USER \"\$site_path/wp-config.local.php\" | cut -d \' -f 4)
    db_password=\$(grep DB_PASSWORD \"\$site_path/wp-config.local.php\" | cut -d \' -f 4)

  echo \"Database: \$db_name User: \$db_user Host: \$db_host\"
  /usr/bin/mariadb-dump -u\"\$db_user\" -p\"\$db_password\" -h\"\$db_host\" \"\$db_name\" --single-transaction --quick --lock-tables=false > \"$FULL_OUT\"
  gzip -f \"$FULL_OUT\"
"; then
    echo "Failed to connect to Hostinger or dump databases"
    devlog -s "FAILED: Could not dump database from shared server"
    exit 1
fi
echo "Database dumped on shared server"
devlog -s "Database dumped on shared server"

echo "Downloading database dumps..."
if ! scp "${SHARED_SERVER_ALIAS}:$FULL_OUT.gz" ~/tmp/; then
    echo "Failed to download full dump"
    devlog -s "FAILED: Could not download database dump"
    exit 1
else
    echo "Full dump downloaded successfully"
    ssh "${SHARED_SERVER_ALIAS}" "rm -f $FULL_OUT.gz"
fi

# drop local database if it exists
if ! mysql -u $localdbuser -p$root_mysql_pass -e "DROP DATABASE IF EXISTS $localdbname"; then
    echo "Failed to drop local database"
    devlog -s "FAILED: Could not drop local database $localdbname"
    exit 1
fi

# create local database
if ! mysql -u $localdbuser -p$root_mysql_pass -e "CREATE DATABASE $localdbname"; then
    echo "Failed to create local database"
    devlog -s "FAILED: Could not create local database $localdbname"
    exit 1
fi

# import full dump (gzipped)
if ! gunzip -c ~/tmp/$FULL_OUT | mysql -u "$localdbuser" -p"$root_mysql_pass" "$localdbname"; then
    echo "Failed to import full dump"
    devlog -s "FAILED: Could not import dump to $localdbname"
    exit 1
fi
echo "Database imported successfully to $localdbname"

# also import/copy it to site domain db
if ! gunzip -c ~/tmp/$FULL_OUT | mysql -u "$localdbuser" -p"$root_mysql_pass" "${SITE_DOMAIN}"; then
    echo "Failed to import full dump to ${SITE_DOMAIN}"
    devlog -s "FAILED: Could not import dump to ${SITE_DOMAIN}"
    exit 1
fi
echo "Database imported successfully to ${SITE_DOMAIN}"

devlog -s "DB import from shared server completed; imported to $localdbname and ${SITE_DOMAIN}"
