#!/bin/bash
password=$(awk -F "=" '/password/ { print $2 ; exit }' /etc/mysql/debian.cnf | tr -d ' ')

mysql -u root <<EOF
GRANT SHUTDOWN ON *.* TO 'debian-sys-maint'@'localhost' IDENTIFIED BY '${password}';
GRANT SELECT ON mysql.user TO 'debian-sys-maint'@'localhost' IDENTIFIED BY '${password}';
EOF

