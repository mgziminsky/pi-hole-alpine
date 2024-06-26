#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Completely uninstalls Pi-hole
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# shellcheck source=advanced/Scripts/COL_TABLE
source "/opt/pihole/COL_TABLE"

while true; do
    read -rp "  ${QST} Are you sure you would like to remove ${COL_WHITE}Pi-hole${COL_NC}? [y/N] " answer
    case ${answer} in
        [Yy]* ) break;;
        * ) echo -e "${OVER}  ${COL_LIGHT_GREEN}Uninstall has been canceled${COL_NC}"; exit 0;;
    esac
done

# Must be root to uninstall
str="Root user check"
if [[ ${EUID} -eq 0 ]]; then
    echo -e "  ${TICK} ${str}"
else
    # Check if sudo is actually installed
    # If it isn't, exit because the uninstall can not complete
    if is_command sudo; then
        export SUDO="sudo"
    else
        echo -e "  ${CROSS} ${str}
            Script called with non-root privileges
            The Pi-hole requires elevated privileges to uninstall"
        exit 1
    fi
fi

readonly PI_HOLE_FILES_DIR="/etc/.pihole"
# shellcheck disable=SC2034
SKIP_INSTALL="true"
source "${PI_HOLE_FILES_DIR}/automated install/basic-install.sh"
# setupVars set in basic-install.sh
# shellcheck disable=SC1090 disable=SC2154
source "${setupVars}"

# package_manager_detect() sourced from basic-install.sh
package_manager_detect

# Uninstall packages used by the Pi-hole
declare -a DEPS
# shellcheck disable=SC2154 # defined in basic-install.sh
if [ -r "${pkgsFile}" ]; then
    readarray -t DEPS < "${pkgsFile}"
else
    DEPS=("${INSTALLER_DEPS[@]}" "${PIHOLE_DEPS[@]}" "${OS_CHECK_DEPS[@]}")
    if [[ "${INSTALL_WEB_SERVER}" == true ]]; then
        # Install the Web dependencies
        DEPS+=("${PIHOLE_WEB_DEPS[@]}")
    fi
fi

# Compatibility
if is_command apt-get; then
    # Debian Family
    PKG_REMOVE=("${PKG_MANAGER}" -y remove --purge)
    package_check() {
        dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -c "ok installed"
    }
elif is_command rpm; then
    # Fedora Family
    PKG_REMOVE=("${PKG_MANAGER}" remove -y)
    package_check() {
        rpm -qa | grep "^$1-" > /dev/null
    }
elif is_command apk; then
    # Alpine Family
    PKG_REMOVE=("${PKG_MANAGER}" del)
    package_check() {
        apk info -qe "$1" > /dev/null
    }
else
    echo -e "  ${CROSS} OS distribution not supported"
    exit 1
fi

removeAndPurge() {
    # Call removeNoPurge to remove Pi-hole specific files
    removeNoPurge

    # Purge dependencies
    echo ""
    if [ -n "$1" ]; then
        ${SUDO} "${PKG_REMOVE[@]}" "${DEPS[@]}"
    else
    for i in "${DEPS[@]}"; do
            if package_check "${i}" &> /dev/null; then
            while true; do
                read -rp "  ${QST} Do you wish to remove ${COL_WHITE}${i}${COL_NC} from your system? [Y/N] " answer
                case ${answer} in
                    [Yy]* )
                        echo -ne "  ${INFO} Removing ${i}...";
                        ${SUDO} "${PKG_REMOVE[@]}" "${i}" &> /dev/null;
                        echo -e "${OVER}  ${INFO} Removed ${i}";
                        break;;
                    [Nn]* ) echo -e "  ${INFO} Skipped ${i}"; break;;
                esac
            done
        else
            echo -e "  ${INFO} Package ${i} not installed"
        fi
    done
    fi

    # Remove dnsmasq config files
    ${SUDO} rm -f /etc/dnsmasq.conf /etc/dnsmasq.conf.orig /etc/dnsmasq.d/*-pihole*.conf &> /dev/null
    echo -e "  ${TICK} Removing dnsmasq config files"
}

removeNoPurge() {
    # Remove FTL
    if is_command pihole-FTL &> /dev/null; then
        echo -ne "  ${INFO} Removing pihole-FTL..."
        stop_service pihole-FTL
    fi

    # Only web directories/files that are created by Pi-hole should be removed
    echo -ne "  ${INFO} Removing Web Interface..."
    # shellcheck disable=SC2154 # defined in basic-install.sh
    ${SUDO} rm -rf "${webroot}/admin" &> /dev/null
    ${SUDO} rm -rf "${webroot}/pihole" &> /dev/null
    ${SUDO} rm -f "${webroot}/index.lighttpd.orig" &> /dev/null

    # If the web directory is empty after removing these files, then the parent html directory can be removed.
    if [ -d "${webroot}" ]; then
        if [[ ! "$(ls -A "${webroot}")" ]]; then
            ${SUDO} rm -rf "${webroot}" &> /dev/null
        fi
    fi
    echo -e "${OVER}  ${TICK} Removed Web Interface"

    # Attempt to preserve backwards compatibility with older versions
    # to guarantee no additional changes were made to /etc/crontab after
    # the installation of pihole, /etc/crontab.pihole should be permanently
    # preserved.
    if [[ -f /etc/crontab.orig ]]; then
        ${SUDO} mv /etc/crontab /etc/crontab.pihole
        ${SUDO} mv /etc/crontab.orig /etc/crontab
        ${SUDO} service cron restart
        echo -e "  ${TICK} Restored the default system cron"
    fi

    # Attempt to preserve backwards compatibility with older versions
    if [[ -f /etc/cron.d/pihole ]];then
        ${SUDO} rm -f /etc/cron.d/pihole &> /dev/null
        echo -e "  ${TICK} Removed /etc/cron.d/pihole"
    fi

    if package_check lighttpd > /dev/null; then
        # Attempt to preserve backwards compatibility with older versions
        if [[ -f /etc/lighttpd/lighttpd.conf.orig ]]; then
            ${SUDO} mv /etc/lighttpd/lighttpd.conf.orig /etc/lighttpd/lighttpd.conf
        fi

        if [[ -f /etc/lighttpd/external.conf ]]; then
            ${SUDO} rm /etc/lighttpd/external.conf
        fi

        # Fedora-based
        if [[ -f /etc/lighttpd/conf.d/pihole-admin.conf ]]; then
            ${SUDO} rm /etc/lighttpd/conf.d/pihole-admin.conf
            conf=/etc/lighttpd/lighttpd.conf
            tconf=/tmp/lighttpd.conf.$$
            if awk '!/^include "\/etc\/lighttpd\/conf\.d\/pihole-admin\.conf"$/{print}' \
              $conf > $tconf && mv $tconf $conf; then
                :
            else
                rm $tconf
            fi
            ${SUDO} chown root:root $conf
            ${SUDO} chmod 644 $conf
        fi

        # Debian-based
        if [[ -f /etc/lighttpd/conf-available/pihole-admin.conf ]]; then
            if is_command lighty-disable-mod ; then
                ${SUDO} lighty-disable-mod pihole-admin > /dev/null || true
            fi
            ${SUDO} rm /etc/lighttpd/conf-available/15-pihole-admin.conf
        fi

        echo -e "  ${TICK} Removed lighttpd configs"
    fi

    ${SUDO} rm -f /etc/dnsmasq.d/adList.conf &> /dev/null
    ${SUDO} rm -f /etc/dnsmasq.d/01-pihole.conf &> /dev/null
    ${SUDO} rm -f /etc/dnsmasq.d/06-rfc6761.conf &> /dev/null
    ${SUDO} rm -rf /var/log/*pihole* &> /dev/null
    ${SUDO} rm -rf /var/log/pihole/*pihole* &> /dev/null
    ${SUDO} rm -rf "${PI_HOLE_CONFIG_DIR}" &> /dev/null
    ${SUDO} rm -rf "${PI_HOLE_FILES_DIR}" &> /dev/null
    ${SUDO} rm -rf "${PI_HOLE_INSTALL_DIR}" &> /dev/null
    ${SUDO} rm -f "${PI_HOLE_BIN_DIR}"/pihole &> /dev/null
    ${SUDO} rm -f /etc/bash_completion.d/pihole &> /dev/null
    ${SUDO} rm -f /etc/sudoers.d/pihole &> /dev/null
    echo -e "  ${TICK} Removed config files"

    # Restore Resolved
    if [[ -e /etc/systemd/resolved.conf.orig ]]; then
        ${SUDO} cp -p /etc/systemd/resolved.conf.orig /etc/systemd/resolved.conf
        systemctl reload-or-restart systemd-resolved
    fi

    ${SUDO} rm -f /etc/systemd/system/pihole-FTL.service
    if [[ -d '/etc/systemd/system/pihole-FTL.service.d' ]]; then
        read -rp "  ${QST} FTL service override directory /etc/systemd/system/pihole-FTL.service.d detected. Do you wish to remove this from your system? [y/N] " answer
        case $answer in
            [yY]*)
                echo -ne "  ${INFO} Removing /etc/systemd/system/pihole-FTL.service.d..."
                ${SUDO} rm -R /etc/systemd/system/pihole-FTL.service.d
                echo -e "${OVER}  ${INFO} Removed /etc/systemd/system/pihole-FTL.service.d"
            ;;
            *) echo -e "  ${INFO} Leaving /etc/systemd/system/pihole-FTL.service.d in place.";;
        esac
    fi
    ${SUDO} rm -f /etc/init.d/pihole-FTL
    ${SUDO} rm -f /usr/bin/pihole-FTL
    echo -e "${OVER}  ${TICK} Removed pihole-FTL"

    # If the pihole manpage exists, then delete and rebuild man-db
    if [[ -f /usr/local/share/man/man8/pihole.8 ]]; then
        ${SUDO} rm -f /usr/local/share/man/man8/pihole.8 /usr/local/share/man/man8/pihole-FTL.8 /usr/local/share/man/man5/pihole-FTL.conf.5
        ${SUDO} mandb -q &>/dev/null
        echo -e "  ${TICK} Removed pihole man page"
    fi

    # If the pihole user exists, then remove
    if id "pihole" &> /dev/null; then
        if ${SUDO} userdel -r pihole 2> /dev/null; then
            echo -e "  ${TICK} Removed 'pihole' user"
        else
            echo -e "  ${CROSS} Unable to remove 'pihole' user"
        fi
    fi
    # If the pihole group exists, then remove
    if getent group "pihole" &> /dev/null; then
        if ${SUDO} groupdel pihole 2> /dev/null; then
            echo -e "  ${TICK} Removed 'pihole' group"
        else
            echo -e "  ${CROSS} Unable to remove 'pihole' group"
        fi
    fi
}

######### SCRIPT ###########
echo -e "  ${INFO} Be sure to confirm if any dependencies should not be removed"
while true; do
    echo -e "  ${INFO} ${COL_YELLOW}The following dependencies may have been added by the Pi-hole install:"
    echo -n "    "
    for i in "${DEPS[@]}"; do
        echo -n "${i} "
    done
    echo "${COL_NC}"
    read -rp "  ${QST} Do you wish to uninstall dependencies? ('Yes' will prompt for each, 'No' will leave all dependencies installed, 'All' will remove all) [Y/n/a] " answer
    case ${answer} in
        [Aa]* ) removeAndPurge force; break;;
        [Yy]* ) removeAndPurge; break;;
        [Nn]* ) removeNoPurge; break;;
        * ) removeAndPurge; break;;
    esac
done

echo -e "\\n   We're sorry to see you go, but thanks for checking out Pi-hole!
    If you need help, reach out to us on GitHub, Discourse, Reddit or Twitter
    Reinstall at any time: ${COL_WHITE}curl -sSL https://install.pi-hole.net | bash${COL_NC}

    ${COL_LIGHT_RED}Please reset the DNS on your router/clients to restore internet connectivity
    ${COL_LIGHT_GREEN}Uninstallation Complete! ${COL_NC}"
