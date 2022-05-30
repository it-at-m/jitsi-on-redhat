# Setup jitsi on redhat-based systems by installing the upstream debian packages

This howto describes how to get jitsi up and running on a redhat-based system using the upstream
debian packages.

If you are not interested in running jitsi on a redhat-based system, this howto may be beneficial
anyway in case you are interested in understanding the structure of debian packages and/or the
process of debugging an error-prone debian package.

This is just a proof of concept, which have been tested at the time of writing his howto in mid
2022, when jitsi had no supported packages for redhat-based systems, which may or may not change in
future. It is in no case the recommended way to operate [jitsi] for several obvious reasons.

This concept is working (at least at the time of writing this howto) as jitsi is based on java and
does not deliver any binary content. However some tweaks needs to be applied in order to overcome
the general differences of debian and redhad systems.

Please note:

 * The potential use of [Alien] have not been evaluated to fulfill the desired task for certain
   reasons. However you may be interested in studying this tool depending on your personal use case.
 * An alternative way to fulfill this task is to [build jitsi from source].
 * This howto does not handle the configuration-fineness of an jitsi setup.
   Following the guides should lead you to a working default system but it may not be the case on
   every machine especially not in the far future. Therefore it is recommended to get jitsi up and
   running on a native debian system in order to gain experience with it in first place. There are a
   lot of howtos focusing on this topic like the [official upstream deployment guide].

Jitsi consists of a range of packages stored in the upstream Repository:

```bash
$ wget 2>/dev/null https://download.jitsi.org/stable/ -O - | cut -d '"' -f 2 | grep deb$ | cut -d _ -f 1 | sort -u | cat -n
     1  jibri
     2  jicofo
     3  jigasi
     4  jitsi-archive-keyring
     5  jitsi-meet
     6  jitsi-meet-prosody
     7  jitsi-meet-tokens
     8  jitsi-meet-turnserver
     9  jitsi-meet-web
    10  jitsi-meet-web-config
    11  jitsi-upload-integrations
    12  jitsi-videobridge
    13  jitsi-videobridge2
```

For our simple setup we will use the following packages:

```
     1	jicofo
     2	jitsi-meet-prosody
     3	jitsi-meet-web
     4	jitsi-meet-web-config
     5	jitsi-videobridge2
```

Note that we will skip the `jitsi-meet` package due to the fact that it is only a meta package and
does not carry essential data:

```bash
cd $(mktemp -d)

repo=https://download.jitsi.org/stable/
wget 2>/dev/null $repo -O - | cut -d '"' -f 2 | grep deb$ | grep ^jitsi-meet_ |
	sort -V  | tail -1 | xargs -I{} wget 2>/dev/null $repo/{}

ar x *.deb

tar -tf data* | cat -n
     1  ./
     2  ./usr/
     3  ./usr/share/
     4  ./usr/share/doc/
     5  ./usr/share/doc/jitsi-meet/
     6  ./usr/share/doc/jitsi-meet/changelog.Debian.gz
     7  ./usr/share/doc/jitsi-meet/copyright

tar -xf control.tar.xz ./control -O | grep Depends | cat -n
     1  Pre-Depends: jitsi-videobridge2 (= 2.1-681-g3544ed05-1)
     2  Depends: jicofo (= 1.0-877-1), jitsi-meet-web (= 1.0.6155-1), jitsi-meet-web-config (= 1.0.6155-1), jitsi-meet-prosody (= 1.0.6155-1)
```


As deb-Packages are simple `ar` archives, we could simply extract the files delivered with the
deb-Packages by running:

```bash
ar x /path/to/deb
sudo tar -xf data.tar* -C /
```

But this approach has some disadvantages:

* Extracted files will not be tracked by a packagemanager and therefore can't be removed easily in
  the future. Of course this information is stored in the package itself.
* All actions performed by the install and removal scripts (contained within `control.tar*`) would
  need to be performed manually.
  * This includes the templating of all config-files.

If you are interested in this approach, please check the [manual installation guide].

## Preparations

### Deactivate SELinux
If SELinux is active on your machine, please make sure to deactivate it during the installation
(and deinstallation) process.

```bash
sudo setenforce 0
sudo setenforce Permissive
```

### Set the appropriate hostname

> Jitsi Meet requires that your server’s hostname matches the hostname that you will use for your
> video conference server. [hostnamequote]

```bash
hostnamectl set-hostname yourserver.example.com
```

### Configure the firewall
Make sure to [Setup and configure your firewall] appropriately. You may leverage `netcat`
to check that. To do so run the following command on the server side:

```bash
sudo nc -l 80 & sudo nc -l 443 & nc -lu 10000 &
```

On the client side, where you will use your browser to connect to jitsi, you could run:

```bash
serveraddress=your_server_address

echo test on port 80 tcp | nc -N $serveraddress 80
echo test on port 443 tcp | nc -N $serveraddress 443
echo test on port 10000 udp | nc -u $serveraddress 10000
```

Again on the serverside you should see this:

```bash
test on port 80 tcp
test on port 443 tcp
test on port 10000 udp
```

If this is not the case, further investigations may be required.

## Install jitsi using the installer-script

After [preparing your system](#Preparations) you should be ready to run the
[install_jitsideb_on_rh.sh](install_jitsideb_on_rh.sh) script. This will guide you through the
installation process and hopefully end up in a running jitsi server.  The script will utilize tested
versions of the above mentioned jitsi packages. If everything works fine, you could use the
[purge_jitsideb_from_rh.sh](./purge_jitsideb_from_rh.sh) script to purge the installation and
execute:

```bash
USE_TESTED_PACKAGES=false ./install_jitsideb_on_rh.sh
```

in order to install the most recent jitsi packages. But it is highly likely that this attempt will
fail in the future and you will be forced to adopt the installation script. Therefore lets go
through the process step by step.

## Process of installing a jitsi package

Lets use `jitsi-videobridge2` as an example package we want to install. For reproduction purposes
lets use the version `2.1-681-g3544ed05-1` of this package. First we need to download it:

```bash
wget https://download.jitsi.org/stable/jitsi-videobridge2_2.1-681-g3544ed05-1_all.deb
```

Now lets try to install this package utilizing `dpkg`. If you have not installed it yet, do it now
all together with `debconf-utils`, a package which is needed as well:

```bash
sudo yum install dpkg debconf-utils

LANG=C sudo dpkg -i jitsi-videobridge2_2.1-681-g3544ed05-1_all.deb
dpkg: regarding jitsi-videobridge2_2.1-681-g3544ed05-1_all.deb containing jitsi-videobridge2, pre-dependency problem:
 jitsi-videobridge2 pre-depends on openjdk-11-jre-headless | openjdk-11-jre | java11-runtime-headless | java11-runtime
  openjdk-11-jre-headless is not installed.
  openjdk-11-jre is not installed.
  java11-runtime-headless is not installed.
  java11-runtime is not installed.

dpkg: error processing archive jitsi-videobridge2_2.1-681-g3544ed05-1_all.deb (--install):
 pre-dependency problem - not installing jitsi-videobridge2
Errors were encountered while processing:
 jitsi-videobridge2_2.1-681-g3544ed05-1_all.deb
```

This attempt obviously failed due to the missing dependencies. So we need to determine the redhat
equivalent of the desired packages as installing the chain of dependencies of all required debian
packages would be a long way to oblivion.

```bash
yum search openjdk | grep 11
java-11-openjdk.x86_64 : OpenJDK 11 Runtime Environment
...
```

The videobridge seems to miss the java runtime environment of `openjdk-11` and `java-11-openjdk`
sounds like a good replacement so lets install that and make it the default java version on the
system:

```bash
yum install java-11-openjdk
sudo update-alternatives --config java
```

Now lets retry the Installation process and instruct dpkg to ignore the missing debian dependency
towards the openjdk packages:

```bash
LANG=C sudo dpkg --ignore-depends=openjdk-11-jre-headless,openjdk-11-jre,java11-runtime-headless,java11-runtime -i jitsi-videobridge2_2.1-681-g3544ed05-1_all.deb
dpkg: regarding jitsi-videobridge2_2.1-681-g3544ed05-1_all.deb containing jitsi-videobridge2, pre-dependency problem:
 jitsi-videobridge2 pre-depends on openjdk-11-jre-headless | openjdk-11-jre | java11-runtime-headless | java11-runtime
  openjdk-11-jre-headless is not installed.
  openjdk-11-jre is not installed.
  java11-runtime-headless is not installed.
  java11-runtime is not installed.

dpkg: warning: ignoring pre-dependency problem!
dpkg: regarding jitsi-videobridge2_2.1-681-g3544ed05-1_all.deb containing jitsi-videobridge2, pre-dependency problem:
 jitsi-videobridge2 pre-depends on libssl3 | libssl1.1
  libssl3 is not installed.
  libssl1.1 is not installed.

dpkg: error processing archive jitsi-videobridge2_2.1-681-g3544ed05-1_all.deb (--install):
 pre-dependency problem - not installing jitsi-videobridge2
Errors were encountered while processing:
 jitsi-videobridge2_2.1-681-g3544ed05-1_all.deb
```

We see that the missing java dependency is now being ignored, but there are some further
unfulfilled dependencies, as `jitsi-videobridge2` requires either `libssl3` or `libssl1.1`.

```bash
LANG=C yum search libssl
No matches found.
```

This time `yum search` does not provide useful information regarding the redhat pendant of this
package. Another approach is to use a debian based system where one of these packages is already
installed or can be installed:

```bash
# on a debian system
dpkg -l | grep libssl # check if libssl is installed
ii  libssl1.1:amd64                       1.1.1f-1ubuntu2.13                    amd64        Secure

dpkg -L libssl1.1 # check the content of that package
/.
/usr
/usr/lib
/usr/lib/x86_64-linux-gnu
/usr/lib/x86_64-linux-gnu/engines-1.1
/usr/lib/x86_64-linux-gnu/engines-1.1/afalg.so
/usr/lib/x86_64-linux-gnu/engines-1.1/capi.so
/usr/lib/x86_64-linux-gnu/engines-1.1/padlock.so
/usr/lib/x86_64-linux-gnu/libcrypto.so.1.1
/usr/lib/x86_64-linux-gnu/libssl.so.1.1
/usr/share
/usr/share/doc
/usr/share/doc/libssl1.1
/usr/share/doc/libssl1.1/NEWS.Debian.gz
/usr/share/doc/libssl1.1/changelog.Debian.gz
/usr/share/doc/libssl1.1/copyright
```

Of course you could gather this information i.e. by exploring a debian repository if you have no
debian system available.

It is quite obvious that the file of interest delivered by the package is `libssl.so.1.1` (the later
part depends on the package version) so lets check what package provides this file in the redhat
world:

```bash
$ LANG=C yum whatprovides libssl.so.*
[...]
openssl3-libs-3.0.1-18.el8.1.x86_64 : A general purpose cryptography library with TLS implementation
[...]
```

`openssl3-libs` sounds good. Thus we would install that, rerun the `dpkg` command and instruct it to
ignore the libssl dependency as well and iterate this process until we find these required debian
package pendants:

Debian Package | redhat Package
---------------|----------------
openjdk-11-jre | java-11-openjdk
libssl3        | openssl3-libs
procps         | procps-ng
uuid-runtime   | uuidd
debconf        | debconf-utils

So we end up with this `dpkg` instruction:

```bash
LANG=C sudo dpkg --ignore-depends=openjdk-11-jre-headless,openjdk-11-jre,java11-runtime-headless,java11-runtime,java8-runtime-headless,java8-runtime,libssl1.1,libssl3,debconf,procps,uuid-runtime -i jitsi-videobridge2_2.1-681-g3544ed05-1_all.deb
[...]
/var/lib/dpkg/info/jitsi-videobridge2.postinst: line 223: deb-systemd-helper: command not found
/var/lib/dpkg/info/jitsi-videobridge2.postinst: line 226: deb-systemd-helper: command not found
/var/lib/dpkg/info/jitsi-videobridge2.postinst: line 233: deb-systemd-helper: command not found
/var/lib/dpkg/info/jitsi-videobridge2.postinst: line 246: deb-systemd-invoke: command not found
/var/lib/dpkg/info/jitsi-videobridge2.postinst: line 253: deb-systemd-helper: command not found
/var/lib/dpkg/info/jitsi-videobridge2.postinst: line 256: deb-systemd-helper: command not found
/var/lib/dpkg/info/jitsi-videobridge2.postinst: line 263: deb-systemd-helper: command not found
```

The dependencies seems to be fulfilled but the installation fails anyway because of the missing
command `deb-systemd-helper` which is launched by the postinst script
`/var/lib/dpkg/info/jitsi-videobridge2.postinst` which in turn comes from the `control.tar*` in
the `*.deb` archive.

Lets again use a debian system in order to determine the Package which delivers this executable:

```bash
# on a debian system
sudo apt install apt-file
sudo apt-file update
apt-file search deb-systemd-helper
init-system-helpers: /usr/bin/deb-systemd-helper
```

So there seem to be a missing dependency towards the `init-system-helpers` package. Moreover there
seem to be no pendant for this package in the redhat world. In fact this binary is not urgently
needed as we could handle systemd unitstarts on our own. There are 2 ways to solve this issue.

1) get rid of the call in the configure script and repack the archive as described above
2) fake the existence of the called binary

For the sake of simplicity we will use the later one and simply generate a symlink towards `true`, a
tool which just exits successfully. In fact we do it for the `deb-systemd-invoke` executable as well
as its absence would trigger the next postinst failure:

```bash
sudo ln -s $(which true) /usr/bin/deb-systemd-helper
sudo ln -s $(which true) /usr/bin/deb-systemd-invoke
```

If we execute the above `dpkg` command, `jitsi-videobridge` should install successfully this time:

```bash
LANG=C dpkg --no-pager -l
Desired=Unknown/Install/Remove/Purge/Hold
| Status=Not/Inst/Conf-files/Unpacked/halF-conf/Half-inst/trig-aWait/Trig-pend
|/ Err?=(none)/Reinst-required (Status,Err: uppercase=bad)
||/ Name               Version             Architecture Description
+++-==================-===================-============-=================================================
ii  jitsi-videobridge2 2.1-681-g3544ed05-1 all          WebRTC compatible Selective Forwarding Unit (SFU)


sudo systemctl restart jitsi-videobridge2.service


sudo systemctl status jitsi-videobridge2.service
● jitsi-videobridge2.service - Jitsi Videobridge
   Loaded: loaded (/lib/systemd/system/jitsi-videobridge2.service; enabled; vendor preset: disabled)
      Active: active (running)...
```

It is important to not only be able to install but also to remove the package from the system. So
let's try that:

```bash
sudo systemctl stop jitsi-videobridge2.service

LANG=C sudo dpkg --force-all --purge jitsi-videobridge2
(Reading database ... 13 files and directories currently installed.)
Purging configuration files for jitsi-videobridge2 (2.1-681-g3544ed05-1) ...
/var/lib/dpkg/info/jitsi-videobridge2.postrm: line 18: deluser: command not found
dpkg: error processing package jitsi-videobridge2 (--purge):
 installed jitsi-videobridge2 package post-removal script subprocess returned error exit status 127
Errors were encountered while processing:
 jitsi-videobridge2
```

The postremoval Script `/var/lib/dpkg/info/jitsi-videobridge2.postrm` seems to use the `deluser`
tool in order to remove a systemuser. `deluser` is a debian specific utility, which pendant would be
`userdel`. These tools have slightly different usage but by looking into the actual script we can
see that it would be save to simply replace these tools:

```bash
grep deluser /var/lib/dpkg/info/jitsi-videobridge2.postrm
            deluser jvb
```

So lets replace `deluser` with `userdel`:

```bash
sudo sed -Ei 's/deluser/userdel/' /var/lib/dpkg/info/jitsi-videobridge2.postrm

LANG=C sudo dpkg --force-all --purge jitsi-videobridge2
(Reading database ... 13 files and directories currently installed.)
Purging configuration files for jitsi-videobridge2 (2.1-681-g3544ed05-1) ...
dpkg: error processing package jitsi-videobridge2 (--purge):
 installed jitsi-videobridge2 package post-removal script subprocess returned error exit status 10
Errors were encountered while processing:
 jitsi-videobridge2
```

This time the error message is not sufficient to determine the source of the error.
In such cases it is recommended to add some debug instructions to the affected control script.
For example one could add the following two lines right after the first Shebang line to make the
script verbose and log all `stderr` output to a file:

```bash
set -x
exec 2> /tmp/examplepath-for-scriptdependend-logfile
```

In case of the affected `rm` script we can simply manipulate the already extracted file on the
system:

```bash
sudo sed -i '2i set -x\nexec 2> /tmp/jitsi-videobridge2.postrm.log' /var/lib/dpkg/info/jitsi-videobridge2.postrm
```

Note: If an `install` script would be affected, one would need to change the script inside the
deb-file by unarchiving and untaring it and repack everything back to a deb archive after applying
the changes. We could do the same with the affected `rm` script to make the changes persistent.

Now we should be able to investigate the error:

```bash
LANG=C sudo dpkg --force-all --purge jitsi-videobridge2

cat /tmp/jitsi-videobridge2.postrm.log
...
+ db_unregister jitsi-videobridge/jvb-hostname
...
+ return 10
```

We notice that the trouble making call is `db_unregister`, a function which is sourced from
`/usr/share/debconf/confmodule` and seems to behave differently on debian systems. Lets accept the
fail of this call by appending `|| true` to the call:

```bash
sudo sed -Ei 's/(db_unregister.*)/\1 || true/' /var/lib/dpkg/info/jitsi-videobridge2.postrm

LANG=C sudo dpkg --purge jitsi-videobridge2
(Reading database ... 148 files and directories currently installed.)
Removing jitsi-videobridge2 (2.1-665-g3a90ccdc-1) ...
Purging configuration files for jitsi-videobridge2 (2.1-665-g3a90ccdc-1) ...
dpkg: warning: while removing jitsi-videobridge2, directory '/usr/share/jitsi-videobridge/lib' not empty so not removed
dpkg: warning: while removing jitsi-videobridge2, directory '/usr/share/doc' not empty so not removed
dpkg: warning: while removing jitsi-videobridge2, directory '/lib' not empty so not removed
dpkg: warning: while removing jitsi-videobridge2, directory '/etc/sysctl.d' not empty so not removed
dpkg: warning: while removing jitsi-videobridge2, directory '/etc/logrotate.d' not empty so not removed
dpkg: warning: while removing jitsi-videobridge2, directory '/etc/jitsi' not empty so not removed
```

This time `jitsi-videobridge2` have been removed successfully. By looking at the above output one
can see that `dpkg` did not delete certain nonempty directories. But it actually deleted something
it shouldn't:

```bash
LANG=c ls /etc/init.d
ls: cannot access '/etc/init.d': No such file or directory
```

On redhat systems `/etc/init.d` is a symlink towards `/etc/rc.d/init.d/` while in the debian world
it is actually a folder. `dpkg` can't handle that and removes the symlink on every purge run. Thus
we need to restore it by running:

```bash
sudo ln -s /etc/rc.d/init.d /etc/init.d
```

## Wrap-up

We took a look on how to install and purge the upstream debian `jitsi-videobridge2` package on a
redhat system. The procedure is quite the same for the remaining packages and the required tweaks
can be looked up in [install_jitsideb_on_rh.sh](./install_jitsideb_on_rh.sh).

[jitsi]: https://jitsi.org/
[Alien]: https://en.wikipedia.org/wiki/Alien_(file_converter)
[build jitsi from source]: https://jitsi.github.io/handbook/docs/devops-guide/devops-guide-manual
[official upstream deployment guide]: https://jitsi.github.io/handbook/docs/devops-guide/devops-guide-quickstart/
[manual installation guide]: ./manual_installation/
[Setup and configure your firewall]: https://jitsi.github.io/handbook/docs/devops-guide/devops-guide-quickstart/#setup-and-configure-your-firewall
[hostnamequote]: https://unixcop.com/install-jitsi-meet-ubuntu/
