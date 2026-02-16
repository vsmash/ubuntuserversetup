#!/usr/bin/env bash

source /etc/app.env

FULL_OUT="db-full-$(date +%Y%m%d%H%M%S).sql"
localdbname="${LOCAL_DB_NAME}"
localdbuser="${LOCAL_DB_USER}"
mkdir -p ~/tmp
source ~/.db_password

devlog -s "DB export to shared server started"

# dump local database
echo "Dumping local database $localdbname..."
if ! mysqldump -u "$localdbuser" -p"$root_mysql_pass" "$localdbname" \
    --single-transaction --quick --lock-tables=false > ~/tmp/"$FULL_OUT"; then
    echo "Failed to dump local database"
    devlog -s "FAILED: Could not dump local database $localdbname"
    exit 1
fi
gzip -f ~/tmp/"$FULL_OUT"
echo "Local database dumped and compressed"
devlog -s "Local database $localdbname dumped successfully"

# upload to shared server
echo "Uploading database dump to shared server..."
if ! scp ~/tmp/"$FULL_OUT.gz" "${SHARED_SERVER_ALIAS}":~/; then
    echo "Failed to upload dump to shared server"
    devlog -s "FAILED: Could not upload dump to shared server"
    exit 1
fi
echo "Dump uploaded to shared server"
devlog -s "Database dump uploaded to shared server"

# import on shared server
echo "Importing database on shared server..."
if ! ssh "${SHARED_SERVER_ALIAS}" "
  set -e
  site_path=\"${SHARED_SITE_PATH}\"
  db_host=\$(grep DB_HOST \"\$site_path/wp-config.php\" | cut -d \' -f 4)
  db_name=\$(grep DB_NAME \"\$site_path/wp-config.local.php\" | cut -d \' -f 4)
  db_user=\$(grep DB_USER \"\$site_path/wp-config.local.php\" | cut -d \' -f 4)
  db_password=\$(grep DB_PASSWORD \"\$site_path/wp-config.local.php\" | cut -d \' -f 4)

  echo \"Importing into \$db_name on \$db_host...\"
  gunzip -c \"$FULL_OUT.gz\" | /usr/bin/mysql -u\"\$db_user\" -p\"\$db_password\" -h\"\$db_host\" \"\$db_name\"
  rm -f \"$FULL_OUT.gz\"
"; then
    echo "Failed to import database on shared server"
    devlog -s "FAILED: Could not import database on shared server"
    exit 1
fi

# clean up local dump
rm -f ~/tmp/"$FULL_OUT.gz"

echo "Database exported and imported successfully"
devlog -s "DB export to shared server completed; exported $localdbname to shared server"
