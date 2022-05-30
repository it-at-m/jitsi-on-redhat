#!/bin/bash -e

UPSTREAM_REPO=${UPSTREAM_REPO:-https://download.jitsi.org/stable/}
PACKAGES_FOLDER=${PACKAGES_FOLDER:-packages}
USE_TESTED_PACKAGES=${USE_TESTED_PACKAGES:-true}
OFFLINE_MODE=${OFFLINE_MODE:-false}
SUDO=sudo

ALL_PACKAGES="jicofo jitsi-meet-web jitsi-meet-web-config jitsi-meet-prosody jitsi-videobridge2"
declare -A PACKAGE_TO_USE
TESTED_PACKAGES="
jicofo_1.0-877-1_all.deb
jitsi-meet-prosody_1.0.6155-1_all.deb
jitsi-meet-web_1.0.6155-1_all.deb
jitsi-meet-web-config_1.0.6155-1_all.deb
jitsi-videobridge2_2.1-681-g3544ed05-1_all.deb
"

die(){ echo >/dev/stderr $*; exit 1; }
errorhandler(){ echo "ERROR! The following command returned with exitcode $1: '$2'."; }
trap 'errorhandler "$?" "${BASH_COMMAND}"' ERR

determine_newest_downloaded_pkg_version(){ find $PACKAGES_FOLDER/ | cut -d '/' -f 2 | grep $1_.*all.deb | sort -V | tail -1; }
determine_newest_upstream_pkg_version(){ grep $1_.*all.deb | sort -V | tail -1 | cut -d '"' -f 2; }
determine_all_dependencies_of_pkg(){ dpkg-deb -I "$1" | grep Depends | cut -d : -f 2 | sed 's/([^)]*)//' | tr '|' ',' | tr -d ' \n'; }

make_sure_pkg_is_present(){
    local pkg=$1
    mkdir -p "$PACKAGES_FOLDER"
    if ! [ -f "$PACKAGES_FOLDER/$pkg" ]; then
        if [ "$OFFLINE_MODE" == false ]; then
            ( cd "$PACKAGES_FOLDER"; wget "$UPSTREAM_REPO/$pkg"; )
        else
            die "Can't ensure the presence of $pkg! Running in offline mode!"
        fi
    fi
}

prepare_upstream_repo_site(){
    if [ -z "$UPSTREAM_REPO_SITE" ]; then
        if [ "$OFFLINE_MODE" == false ]; then
            UPSTREAM_REPO_SITE=$(wget -O - $UPSTREAM_REPO)
        else
            die "Running in offline mode"
        fi
    fi
}

select_and_download_jitsi_debian_packages(){
    local pkg
    for pkg in $ALL_PACKAGES; do
        if [ "$USE_TESTED_PACKAGES" == true ]; then
            PACKAGE_TO_USE[$pkg]=$(grep ^${pkg}_ <<< "$TESTED_PACKAGES")
            [ -n "${PACKAGE_TO_USE[$pkg]}" ]
            make_sure_pkg_is_present ${PACKAGE_TO_USE[$pkg]}
        else # use available packages
            if [ "$OFFLINE_MODE" == false ]; then
                prepare_upstream_repo_site
                PACKAGE_TO_USE[$pkg]=$(determine_newest_upstream_pkg_version $pkg <<< "$UPSTREAM_REPO_SITE")
                [ -n "${PACKAGE_TO_USE[$pkg]}" ]
                make_sure_pkg_is_present ${PACKAGE_TO_USE[$pkg]}
            else #OFFLINE_MODE
                PACKAGE_TO_USE[$pkg]=$(determine_newest_downloaded_pkg_version $pkg)
                if [ -n "${PACKAGE_TO_USE[$pkg]}" ]; then
                    die "Running in offline mode and missing predownloaded version of package: $pkg"
                fi
            fi
        fi
    done
}

make_java11_sysdefault(){
    if </dev/null update-alternatives --config java 2>/dev/null | grep '^.+' | grep -q java-11-openjdk; then
        : java-11 seems to be already the default
    else
        read -p 'Hit enter and choose java-11 in the upcomming selection'
        $SUDO update-alternatives --config java
    fi
}

install_generally_required_packages(){
    $SUDO yum install dpkg debconf-utils
    $SUDO yum install java-11-openjdk
    make_java11_sysdefault
}

install_package(){
    local pkg="./$PACKAGES_FOLDER/${PACKAGE_TO_USE[$1]}"
    $SUDO dpkg "--ignore-depends=$(determine_all_dependencies_of_pkg "$pkg")" -i "$pkg"
}

install_jitsi_videobridge2(){
    $SUDO yum install openssl3-libs # replacement for libssl3 dependency
    $SUDO yum install procps-ng uuidd # replacement for procs dependendy

    $SUDO ln -s /lib/systemd/system/jitsi-videobridge2.service /usr/lib/systemd/system/ || true

    $SUDO ln -s $(which true) /usr/bin/deb-systemd-invoke || true
    $SUDO ln -s $(which true) /usr/bin/deb-systemd-helper || true

    read -p "You probably want to answer the upcomming question with: $(hostname)"$'\nHit enter to continue...' _

    install_package jitsi-videobridge2

    $SUDO systemctl enable jitsi-videobridge2.service
    $SUDO systemctl start jitsi-videobridge2.service

    # db_unregister (source: /usr/share/debconf/confmodule) seems not work appropriately on rh-based systems
    # thus remove this call from postrm script in order to be able to remove the package successfully in the future
    $SUDO sed -Ei 's/(db_unregister.*)/\1 || true/' /var/lib/dpkg/info/jitsi-videobridge2.postrm

    # replace deluser with userdel to prevent the postrm script from failing
    $SUDO sed -Ei 's/deluser/userdel/' /var/lib/dpkg/info/jitsi-videobridge2.postrm
}

install_jicofo(){
    $SUDO yum install rubygem-hocon jq

    # Fake the existance of init-system-helpers debian-package
    [ -x "/usr/bin/update-rc.d" ] || $SUDO ln -s /usr/bin/true /usr/bin/update-rc.d
    [ -x "/usr/bin/invoke-rc.d" ] || $SUDO ln -s /usr/bin/true /usr/bin/invoke-rc.d

    # Fake the existance of lsb-base debian-package
    $SUDO mkdir -p /lib/lsb/
    $SUDO ln -s /dev/null /lib/lsb/init-functions || true

    install_package jicofo

    $SUDO systemctl daemon-reload
    $SUDO systemctl enable jicofo.service
    $SUDO systemctl start jicofo.service

    # replace deluser with userdel to prevent the postrm script from failing
    $SUDO sed -Ei 's/deluser/userdel/' /var/lib/dpkg/info/jicofo.postrm
}

install_jitsi_meet_web_config(){
    $SUDO yum install nginx openssl

    # file is delivered by openssl package but missing in rh
    $SUDO cp openssl.cnf /etc/ssl/

    install_package jitsi-meet-web-config
}

install_jitsi_meet_web(){
    $SUDO dpkg -i "./$PACKAGES_FOLDER/${PACKAGE_TO_USE[jitsi-meet-web]}"
}

install_jitsi_meet_prosody(){
    $SUDO yum install prosody lua-sec openssl

    $SUDO ln -s /etc/pki/ca-trust/source/anchors/ /usr/local/share/ca-certificates  || true
    $SUDO ln -s /usr/bin/update-ca-trust /usr/bin/update-ca-certificates || true

    install_package jitsi-meet-prosody
}

install_jitsi_meet(){
    install_jitsi_videobridge2

    install_jicofo
    # We are not installing jitsi-meet itself as it does not provide essential content
    install_jitsi_meet_web_config
    install_jitsi_meet_web
    install_jitsi_meet_prosody

    $SUDO systemctl restart jitsi-videobridge2.service jicofo.service prosody.service
}

main(){
    cd "$(dirname "$0")"
    if [ "$(whoami)" == root ]; then
        SUDO=''
    fi

    select_and_download_jitsi_debian_packages

    install_generally_required_packages
    install_jitsi_meet
    echo "Jitsi installation finished"
}

main
