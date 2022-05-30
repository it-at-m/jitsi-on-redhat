# Setup jitsi on redhat-based systems by extracting the upstream debian packages

This is an alternative solution for the task described in the [jitsi dpkg installation guide].
Please make sure to read that howto first, including the [preparations-section].

The following instructions will guide you through the process of manually download and extract the
most recent version of jitsi packages which are required for a minimal working setup. The
[configs](./configs/) folder will serve as a template for the actual configuration.
Please note that the template may not valid for the future versions of jitsi and would need to be
adjusted.

## Preconditions

First we will randomly generate a secrets-file, which will be sourced in the setup-process and deleted at the end.
The `CHARSET` and `SECRETLENGTH` may be adjusted to achieve the desired security needs.

```bash
CHARSET='[:alpha:][:digit:]'
SECRETLENGTH=16

cat << EOF > /var/tmp/jitsi_setup_secrets
PROSODY_FOCUS_SECRET=$(cat /dev/urandom | tr -dc "$CHARSET" | fold -w ${1:-$SECRETLENGTH} | head -1)
JVB_SECRET=$(cat /dev/urandom | tr -dc "$CHARSET" | fold -w ${1:-$SECRETLENGTH} | head -1)
EOF
```

Next install java:

```bash
sudo yum install java-latest-openjdk #or check the deb-dependencies to determine the required java-version
sudo update-alternatives --config java # select the installed version
```

Create required users and folders:

```bash
sudo groupadd jitsi
sudo useradd -r -g jitsi --shell /bin/bash --create-home -d /usr/share/jitsi-videobridge jvb

sudo useradd -r -g jitsi --shell /bin/bash --create-home -d /usr/share/jicofo jicofo

sudo mkdir /var/log/jitsi/
sudo chown jvb:jitsi /var/log/jitsi
sudo chmod 770 /var/log/jitsi/
```

Generate the config-files from template:

```bash
# git clone this repo and cd into the folder of this README.md

sudo cp -r configs/* /etc/
(
	sudo find /etc/jitsi/ -type f
	echo /etc/nginx/conf.d/jitsi.conf
	echo /etc/nginx/conf.d/jitsi.conf
    echo /etc/prosody/conf.d/template_cfg_lua
) | sudo xargs -I {} sed -i "s/{{ HOSTNAME }}/$(hostname)/g" {}

source /var/tmp/jitsi_setup_secrets
sudo sed -i "s/{{ PROSODY_FOCUS_SECRET }}/$PROSODY_FOCUS_SECRET/g" /etc/jitsi/jicofo/config
sudo sed -i "s/{{ JVB_SECRET }}/$JVB_SECRET/g" /etc/jitsi/videobridge/sip-communicator.properties /etc/jitsi/videobridge/config

sudo chown -R jicofo:jitsi /etc/jitsi/jicofo/
```

## Configure jitsi meet web

```bash
cd /etc/jitsi/meet/
sudo openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:4096 -keyout jitsi.key -out jitsi.crt
```

```bash
cd $(mktemp -d) # or enter another empty folder
pkg=jitsi-meet-web
up2date_deb=$(wget -O - https://download.jitsi.org/stable/  | grep ${pkg}_ | cut -d '"' -f 2 | grep deb | sort -Vr | head -1)

wget "https://download.jitsi.org/stable/$up2date_deb"
ar x $up2date_deb
sudo tar -xf data.tar* -C /

# cleanup the generated files if you wish
```

```bash
cd $(mktemp -d) # or enter another empty folder
pkg=jitsi-meet-web-config
up2date_deb=$(wget -O - https://download.jitsi.org/stable/  | grep ${pkg}_ | cut -d '"' -f 2 | grep deb | sort -Vr | head -1)

wget "https://download.jitsi.org/stable/$up2date_deb"
tar -xf data.tar.xz --to-stdout ./usr/share/jitsi-meet-web-config/config.js | sed "s/jitsi-meet.example.com/$(hostname)/g" | sudo tee >/dev/null /etc/jitsi/meet/config.js

# cleanup the generated files if you wish
```

## Configure nginx

```bash
sudo yum install nginx
sudo systemctl enable nginx.service
sudo systemctl start nginx.service
```

## Configure jitsi-videobridge

```bash
cd $(mktemp -d) # or enter another empty folder
pkg=jitsi-videobridge2
up2date_deb=$(wget -O - https://download.jitsi.org/stable/  | grep ${pkg}_ | cut -d '"' -f 2 | grep deb | sort -Vr | head -1)

wget "https://download.jitsi.org/stable/$up2date_deb"
ar x $up2date_deb
tar -tf data.tar.xz | grep -v '^./etc/' | grep -v '^./lib/' | sed 1d | sudo tar -xf data.tar.xz -C / -T /dev/stdin
echo './lib/systemd/system/jitsi-videobridge2.service' | sudo tar -xf data.tar.xz -C /usr/lib/systemd/system/ -T /dev/stdin  --strip-components=4
sudo systemctl daemon-reload
sudo systemctl start jitsi-videobridge2.service

# cleanup the generated files if you wish
```

## Configure jicofo

`dpkg` is required for `start-stop-daemon`, which is launched by `/etc/init.d/jicofo`

```bash
sudo yum install dpkg
```

```bash
cd $(mktemp -d) # or enter another empty folder
pkg=jicofo
up2date_deb=$(wget -O - https://download.jitsi.org/stable/  | grep ${pkg}_ | cut -d '"' -f 2 | grep deb | sort -Vr | head -1)

wget "https://download.jitsi.org/stable/$up2date_deb"
ar x $up2date_deb
( echo ./usr/share/jicofo/; echo ./etc/init.d/jicofo; ) | sudo tar -xf data.tar.xz -C / -T /dev/stdin
sudo sed -Ei 's#(/lib/lsb/init-functions)#/usr\1#g' -i /etc/rc.d/init.d/jicofo

sudo systemctl daemon-reload
sudo systemctl enable jicofo
sudo systemctl start jicofo

# cleanup the generated files if you wish
```

## Configure prosody

```bash
sudo yum install prosody
sudo systemctl enable prosody.service

sudo ln -s template_cfg_lua /etc/prosody/conf.d/$(hostname).cfg.lua

source /var/tmp/jitsi_setup_secrets
sudo prosodyctl register jvb auth.$(hostname) $JVB_SECRET
sudo prosodyctl register focus auth.$(hostname) $PROSODY_FOCUS_SECRET
sudo prosodyctl mod_roster_command subscribe focus.$(hostname) focus@auth.$(hostname)
```

* Install the prosody plugins

```bash
cd $(mktemp -d) # or enter another empty folder
pkg=jitsi-meet-prosody
up2date_deb=$(wget -O - https://download.jitsi.org/stable/  | grep ${pkg}_ | cut -d '"' -f 2 | grep deb | sort -Vr | head -1)

wget "https://download.jitsi.org/stable/$up2date_deb"
ar x $up2date_deb
sudo tar -xf data.tar.xz -C /

# cleanup the generated files if you wish
```

```bash
sudo prosodyctl cert generate $(hostname)

sudo prosodyctl cert generate auth.$(hostname)
```

Now add the auth-cert to `/etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt`:

```bash
sudo ln -sf /var/lib/prosody/auth.$(hostname).crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust
```

```bash
sudo systemctl restart prosody
```

## Last step

Shred (or simply remove) the initially created secrets file:

```bash
shred -vzun1 /var/tmp/jitsi_setup_secrets
```

[jitsi dpkg installation guide]: ../README.md
[preparations-section]: ../README.md#preparations
