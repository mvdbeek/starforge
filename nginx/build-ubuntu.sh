#!/bin/bash
# tested for ubuntu trusty, wily and xenial
set -e

. /etc/os-release


apt-get -qq update && apt-get install -y lsb-release tzdata

TAG=2.3.0
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pkg=nginx
dch_message="Restore the nginx-upload module from tag $TAG in Github, compatible with nginx 1.x."
DEBFULLNAME="${DEBFULLNAME:-Nathan Coraor}"
DEBEMAIL="${DEBEMAIL:-nate@bx.psu.edu}"
PPA="${PPA:-ppa:natefoo/nginx}"
GPG_KEY="${GPG_KEY:-/gpg_key.asc}"
export DEBFULLNAME DEBEMAIL PPA GPG_KEY
dch_dist=$(lsb_release -cs)
build=/host/build.$(hostname)
build_deps="git dpkg-dev debhelper debian-keyring devscripts dput ca-certificates build-essential fakeroot gnupg2"
build_deps_bionic="libexpat-dev libgd-dev libgeoip-dev libhiredis-dev libluajit-5.1-dev libmhash-dev libpam0g-dev libpcre3-dev libperl-dev libssl-dev libxslt1-dev quilt zlib1g-dev"
echo -e "Building for Ubuntu-$dch_dist\n"

# set timezone for debian/changelog
echo 'America/New_York' > /etc/timezone
dpkg-reconfigure debconf -f noninteractive tzdata
apt-get install --no-install-recommends -y $build_deps
if [ "$dch_dist" == 'bionic' ]; then
    apt-get install --no-install-recommends -y $build_deps_bionic
fi
mkdir -p $build
cd $build
if [ "$dch_dist" != 'trusty' ]; then
    apt-get install -y dh-systemd
fi
if [ "$dch_dist" == 'yakkety' -o "$dch_dist" == 'xenial' -o "$dch_dist" == 'trusty' -o "$dch_dist" == 'bionic' ]; then
    sed -i s'/# deb-src/deb-src/' /etc/apt/sources.list
    apt-get update
elif [ "$NAME" == 'Debian GNU/Linux' ] && [ "$VERSION" == "8 (jessie)" ]; then
    cp /etc/apt/sources.list /etc/apt/sources.list.bak
    sed -i s'/deb/deb-src/' /etc/apt/sources.list
    cat /etc/apt/sources.list.bak >> /etc/apt/sources.list
    apt-get update
fi
apt-get source $pkg
distrib_version=$(grep Version: *.dsc| cut -d' ' -f2-| head -n1)
nginx_version=$(ls *.orig.tar.gz|sed 's/\.orig\.tar\.gz//'|sed 's/nginx_//g')
ppa_version=${distrib_version}ppa1
git clone -b "$TAG" --single-branch https://github.com/fdintino/nginx-upload-module.git/ \
    nginx-${nginx_version}/debian/modules/nginx-upload
upload_module_shortrev=$(git --git-dir=nginx-${nginx_version}/debian/modules/nginx-upload/.git rev-parse --short HEAD)
rm -rf nginx/debian/modules/nginx-upload/.git
if [ "$dch_dist" != 'bionic' ]; then
    sed -e '/^ #Removed as it no longer works with 1.3.x and above.$/d' \
        -e 's/^ #\(nginx-upload\)$/ \1/' \
        -e "s%^ #\( Homepage: https://github.com\)/vkholodkov/nginx-upload-module$% \1/fdintino/nginx-upload-module/tree/$TAG%" \
        -e "s/^ # Version: 2.2.0.*$/  Version: ${TAG}-${upload_module_shortrev}/" \
        -i nginx-${nginx_version}/debian/modules/README.Modules-versions
fi

if [ "$dch_dist" == 'bionic' ]; then
    sed -e 's#^\(\t*\)\(--add-dynamic-module=$(MODULESDIR)/http-auth-pam \\\)#\1--add-module=$(MODULESDIR)/nginx-upload \\\n\1\2#' \
    -i nginx-${nginx_version}/debian/rules
elif [ "$dch_dist" == 'trusty' ]; then
    sed -e 's#\(^\t    --add-module=$(MODULESDIR)/nginx-upload-progress \\\)#\t    --add-module=$(MODULESDIR)/nginx-upload \\\n\1#' \
    -i nginx-${nginx_version}/debian/rules
else
    sed -e 's#\(\t\t\t--add-module=$(MODULESDIR)/nginx-upload-progress \\\)#\t\t\t--add-module=$(MODULESDIR)/nginx-upload \\\n\1#' \
    -i nginx-${nginx_version}/debian/rules
fi

cd nginx-${nginx_version}
dch -v ${ppa_version} --force-distribution -D "${dch_dist}" "${dch_message}"
debuild -S -sd -us -uc
if [ -f "$GPG_KEY" ]; then
    echo "Signing source.changes and uploading to ppa"
    gpg2 --import --batch "$GPG_KEY"
    debsign -p "gpg2 --batch" -S ${build}/${pkg}_${ppa_version}_source.changes
    if [ "$VERSION" == "8 (jessie)" ];then
        dput -c $DIR/dput.cf  -u "$PPA" $build/${pkg}_${ppa_version}_source.changes
    else
        dput -u "$PPA" $build/${pkg}_${ppa_version}_source.changes
    fi
else
    echo "To sign: debsign -S ${pkg}_${ppa_version}_source.changes"
    echo "To push: dput "$PPA" ${pkg}_${ppa_version}_source.changes"
fi
