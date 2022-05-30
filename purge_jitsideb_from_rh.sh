#!/bin/bash -e

deactivate_selinux(){
    echo deactivating SELinux
    sudo setenforce 0
    sudo setenforce Permissive
}

main(){
    echo "SELinux needs to be deactivated for 'dpkg --purge' to work."
    echo "Please make sure SELinux is deactivated or type 'deactivate' to deactivate it now."
    echo "Hit enter to continue..."
    local userinput
    read -p '> ' userinput
    [ "$userinput" = deactivate ] && deactivate_selinux || true

    sudo pkill -f java.*jvb
    sudo dpkg --force-all --purge jicofo jitsi-meet-prosody jitsi-meet-web jitsi-meet-web-config init-system-helpers jitsi-videobridge2

    sudo ln -s /etc/rc.d/init.d /etc/init.d || true

    for symlink in  /usr/bin/update-rc.d /usr/bin/invoke-rc.d /usr/bin/update-ca-certificates \
                    /lib/lsb/init-functions /usr/lib/systemd/system/jitsi-videobridge2.service \
                    /usr/local/share/ca-certificates /lib/lsb/init-functions \
                    /usr/bin/deb-systemd-helper /usr/bin/deb-systemd-invoke
    do
        [ -L "$symlink" ] && sudo rm "$symlink"
    done

    sudo rmdir /lib/lsb/ || true

    echo done
}

main
