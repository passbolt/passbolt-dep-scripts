#!/usr/bin/env bash

set -euo pipefail

if [ $(id -u) -gt 0 ]
then
  echo "You need to launch this script as root user (or use sudo) !"
  exit 1
fi

LC_ALL="en_US.UTF-8"
LC_CTYPE="en_US.UTF-8"
PASSBOLT_FLAVOUR=ce
PASSBOLT_BRANCH=stable

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
cd ${SCRIPT_DIR}

## OS Detection
os_detect () {
  if [ -f /etc/debian_version ]
  then
      PACKAGE_MANAGER=apt
      DEBIAN_RECOMMENDS=''
      DISTRONAME=$(grep -E "^ID=" /etc/os-release | awk -F= '{print $2}')
      # CODENAME used for Debian family
      CODENAME=$(grep -E "^VERSION_CODENAME=" /etc/os-release | awk -F= '{print $2}' || true)
  
      # We use buster debian package for bullseye
      if [ "${CODENAME}" = "bullseye" ]
      then
          CODENAME="buster"
      fi
  elif which zypper > /dev/null 2>&1
  then
      PACKAGE_MANAGER=zypper
      echo "OpenSuse is not yet supported"
      exit 1
  elif which dnf > /dev/null 2>&1
  then
      PACKAGE_MANAGER=dnf
  elif which yum > /dev/null 2>&1
  then
      PACKAGE_MANAGER=yum
  else
      echo "Can't find compatible operating system"
      echo "Exit"
      exit 1
  fi

  # RHEL Family get OS major version (7, 8, 9)
  if [ "${PACKAGE_MANAGER}" = "yum" ] || [ "${PACKAGE_MANAGER}" = "dnf" ]
  then
      if ! which bc > /dev/null 2>&1
      then
          ${PACKAGE_MANAGER} install -y bc
      fi
      ${PACKAGE_MANAGER} clean all > /dev/null
      OS_VERSION=$(grep -E '^VERSION_ID=' /etc/os-release | awk -F= '{print $2}' | sed 's/\"//g')
      OS_VERSION_MAJOR=$(echo ${OS_VERSION:0:1} | bc)
  fi 
  
  if [ "$(grep -E "^ID=" /etc/os-release | awk -F= '{print $2}' | sed 's/"//g')" = "ol" ] && [ "${OS_VERSION_MAJOR}" = "7" ]
  then
      echo "Oracle Linux 7 not supported"
      echo "Exit"
      exit 1
  fi
}

install_dependencies () {
  if [ "${PACKAGE_MANAGER}" = "apt" ]
  then
    ${PACKAGE_MANAGER} update
    ${PACKAGE_MANAGER} install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      gnupg-agent \
      software-properties-common \
      haveged \
      certbot \
      wget \
      python3-certbot-nginx
  elif [ "${PACKAGE_MANAGER}" = "yum" ] || [ "${PACKAGE_MANAGER}" = "dnf" ]
  then
    if [ "$(grep -E "^ID=" /etc/os-release | awk -F= '{print $2}' | sed 's/"//g')" = "ol" ]
    then
      # Oracle Linux
      ${PACKAGE_MANAGER} install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-${OS_VERSION_MAJOR}.noarch.rpm
    else
      ${PACKAGE_MANAGER} install -y epel-release
    fi
    ${PACKAGE_MANAGER} install -y https://rpms.remirepo.net/enterprise/remi-release-${OS_VERSION_MAJOR}.rpm
    if [ ${OS_VERSION_MAJOR} -eq 7 ]
    then
      ${PACKAGE_MANAGER} install -y certbot python-certbot-nginx wget
      ${PACKAGE_MANAGER} install -y yum-utils
      yum-config-manager --disable 'remi-php*'
      yum-config-manager --enable   remi-php74
    else
      ${PACKAGE_MANAGER} install -y certbot python3-certbot-nginx wget
      ${PACKAGE_MANAGER} module -y reset php
      ${PACKAGE_MANAGER} module -y install php:remi-7.4
    fi
  fi
}

setup_repository () {
  if [ "${PACKAGE_MANAGER}" = "apt" ]
  then
    curl -s https://download.passbolt.com/pub.key | gpg --dearmor | tee /usr/share/keyrings/passbolt-repository.gpg > /dev/null
    chmod 644 /usr/share/keyrings/passbolt-repository.gpg

    cat << EOF | tee /etc/apt/sources.list.d/passbolt.sources > /dev/null
Types: deb
URIs: https://download.passbolt.com/${PASSBOLT_FLAVOUR}/${DISTRONAME}
Suites: ${CODENAME}
Components: ${PASSBOLT_BRANCH}
Signed-By: /usr/share/keyrings/passbolt-repository.gpg
EOF
    apt update
  elif [ "${PACKAGE_MANAGER}" = "yum" ] || [ "${PACKAGE_MANAGER}" = "dnf" ]
  then
    cat << EOF | tee /etc/yum.repos.d/passbolt.repo
[passbolt-server]
name=Passbolt Server
baseurl=https://download.passbolt.com/${PASSBOLT_FLAVOUR}/rpm/el${OS_VERSION_MAJOR}/${PASSBOLT_BRANCH}
enabled=1
gpgcheck=1
gpgkey=https://download.passbolt.com/pub.key
EOF
  fi
  # Add MariaDB 10.5 repository for CentOS 7
  if [ "${PACKAGE_MANAGER}" = "yum" ]
  then
    cat << EOF | tee /etc/yum.repos.d/mariadb.repo
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.3/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF
  fi
}

install_passbolt () {
  if [ "${PACKAGE_MANAGER}" = "apt" ]
  then
    ${PACKAGE_MANAGER} install -y passbolt-${PASSBOLT_FLAVOUR}-server
  elif [ "${PACKAGE_MANAGER}" = "yum" ] || [ "${PACKAGE_MANAGER}" = "dnf" ]
  then
    ${PACKAGE_MANAGER} install -y passbolt-${PASSBOLT_FLAVOUR}-server
  fi
}

# Main
os_detect
install_dependencies
setup_repository
#install_passbolt