#!/usr/bin/env sh

# Touch files to ensure they exist (create if non-existing, preserve if existing)
# shellcheck disable=SC2174
mkdir -pm 0755 /run/pihole /var/log/pihole
chown -R pihole:pihole /etc/pihole/ /var/log/pihole/
# allow pihole to access subdirs in /etc/pihole (sets execution bit on dirs)
find /etc/pihole/ /var/log/pihole/ -type d -exec chmod 0755 {} +
# Set all files (except TLS-related ones) to u+rw g+r
find /etc/pihole/ /var/log/pihole/ -type f ! \( -name '*.pem' -o -name '*.crt' \) -exec chmod 0640 {} +
# Set TLS-related files to a more restrictive u+rw *only* (they may contain private keys)
find /etc/pihole/ -type f \( -name '*.pem' -o -name '*.crt' \) -exec chmod 0600 {} +

[ -f /var/log/pihole/FTL.log ] || install -m 640 -o pihole -g pihole /dev/null /var/log/pihole/FTL.log
[ -f /var/log/pihole/pihole.log ] || install -m 640 -o pihole -g pihole /dev/null /var/log/pihole/pihole.log
[ -f /var/log/pihole/webserver.log ] || install -m 640 -o pihole -g pihole /dev/null /var/log/pihole/webserver.log
[ -f /etc/pihole/dhcp.leases ] || install -m 644 -o pihole -g pihole /dev/null /etc/pihole/dhcp.leases
