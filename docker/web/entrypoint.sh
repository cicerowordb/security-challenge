#!/usr/bin/env bash
set -euo pipefail

DB_NAME="dvwa"
DB_USER="dvwa"
DB_PASS="dvwa"

mkdir -p /run/mysqld
chown mysql:mysql /run/mysqld

if [[ ! -d /var/lib/mysql/mysql ]]; then
  mariadb-install-db --user=mysql --datadir=/var/lib/mysql >/dev/null
fi

/usr/sbin/mariadbd \
  --user=mysql \
  --datadir=/var/lib/mysql \
  --socket=/run/mysqld/mysqld.sock \
  --bind-address=127.0.0.1 &
MYSQL_PID=$!

for _ in $(seq 1 60); do
  if mariadb-admin --socket=/run/mysqld/mysqld.sock ping >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! mariadb-admin --socket=/run/mysqld/mysqld.sock ping >/dev/null 2>&1; then
  echo "MariaDB nao iniciou" >&2
  exit 1
fi

mariadb --socket=/run/mysqld/mysqld.sock -u root <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

cat > /var/www/html/DVWA/config/config.inc.php <<'PHP'
<?php
$DBMS = 'MySQL';

$_DVWA = array();
$_DVWA[ 'db_server' ]   = '127.0.0.1';
$_DVWA[ 'db_database' ] = 'dvwa';
$_DVWA[ 'db_user' ]     = 'dvwa';
$_DVWA[ 'db_password' ] = 'dvwa';
$_DVWA[ 'db_port' ]     = '3306';

$_DVWA[ 'recaptcha_public_key' ]  = '';
$_DVWA[ 'recaptcha_private_key' ] = '';

$_DVWA[ 'default_security_level' ] = 'low';
$_DVWA[ 'default_locale' ] = 'en';
$_DVWA[ 'disable_authentication' ] = false;

define('MYSQL', 'mysql');
define('SQLITE', 'sqlite');
$_DVWA[ 'SQLI_DB' ] = MYSQL;
?>
PHP

chown -R www-data:www-data /var/www/html/DVWA

cat > /etc/apache2/conf-available/dvwa.conf <<'APACHE'
<Directory /var/www/html/DVWA>
    AllowOverride All
    Require all granted
</Directory>
APACHE

a2enconf dvwa >/dev/null
a2enmod rewrite >/dev/null

apache2ctl -D FOREGROUND &
APACHE_PID=$!

trap 'kill "$MYSQL_PID" "$APACHE_PID" 2>/dev/null || true' TERM INT
wait -n "$MYSQL_PID" "$APACHE_PID"
