#!/usr/bin/env bash

set -euo pipefail

if [ "$(id -u)" -gt 0 ]
then
  echo "You need to launch this script as root user (or use sudo) !"
  exit 1
fi

LC_ALL="en_US.UTF-8"
LC_CTYPE="en_US.UTF-8"
PASSBOLT_FLAVOUR="ce"
PASSBOLT_BRANCH="stable"
PASSBOLT_KEYRING_FILE="/usr/share/keyrings/passbolt-repository.gpg"
PASSBOLT_FINGERPRINT="3D1A0346C8E1802F774AEF21DE8B853FC155581D"

# shellcheck source=/dev/null
source /etc/os-release

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
cd "${SCRIPT_DIR}"

_error_exit () {
  MESSAGE=${1:-Unknown error}
  echo "${MESSAGE}"
  echo "Exit"
  exit 1
}

passboltMigrate=0

while :; do
    case ${1-default} in
        --passbolt-migrate)
            passboltMigrate=1
            ;;
        --)              # End of all options.
            shift
            break
            ;;
        -?*)
            printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
            ;;
        *)               # Default case: No more options, so break out of the loop.
            break
    esac

    shift
done

function is_supported_distro() {
    local DISTROS=(
            "debian12"
            "debian13"
            "raspbian"
            "ubuntu24"
            "rhel9"
            "rocky9"
            "ol9"
            "almalinux9"
            "opensuse-leap15"
            # Adding SLES15
            "sles15"
          )
    for DISTRO in "${DISTROS[@]}"
    do
      # the ${VERSION_ID%.*} pattern is to remove minor version, aka rhel8 for rhel8.6
      [[ "${ID}${VERSION_ID%.*}" = ${DISTRO}* ]] && return 0
    done
    return 1
}

compliance_check () {
  local NOT_SUPPORTED_DISTRO="Unfortunately, ${PRETTY_NAME:-This Linux distribution} is not supported :-("
  if ! is_supported_distro; then
    _error_exit "${NOT_SUPPORTED_DISTRO}"
  fi
  local IPV6_ERROR="Your server has no IPv6 support"
  if ! sysctl -a | grep disable_ipv6 > /dev/null
  then
    _error_exit "${IPV6_ERROR}"
  fi
  if [ ${passboltMigrate} -eq 0 ]
  then
    local PHP_ERROR="PHP is already installed, you must execute this script on a vanilla server"
    if [ -f /usr/bin/dpkg ]
    then
      if dpkg -l | grep php > /dev/null
      then
        _error_exit "${PHP_ERROR}"
      fi
    fi
    if [ -f /usr/bin/rpm ]
    then
      if rpm -qa | grep php > /dev/null
      then
        _error_exit "${PHP_ERROR}"
      fi
      if rpm -qa | grep remi-release > /dev/null
      then
        _error_exit "remi-release is already installed, please remove it before executing this script"
      fi
    fi
  fi
}

## OS Detection
os_detect () {
  if [ -f /etc/debian_version ]
  then
      PACKAGE_MANAGER=apt

      # The section below is used to generate passbolt sources.list
      DISTRONAME=$(grep -E "^ID=" /etc/os-release | awk -F= '{print $2}')
      # CODENAME used for Debian family
      CODENAME=$(grep -E "^VERSION_CODENAME=" /etc/os-release | awk -F= '{print $2}' || true)

      # Handle Raspberry PI raspbian OS
      if [ "${DISTRONAME}" = "raspbian" ]
      then
          DISTRONAME="debian"
      fi
      # We use buster debian package for bullseye
      if [ "${CODENAME}" = "bullseye" ]
      then
          CODENAME="buster"
      elif [ "${CODENAME}" = "bookworm" ]
      then
          CODENAME="buster"
      # We use focal ubuntu package for jammy
      elif [ "${CODENAME}" = "jammy" ]
      then
          CODENAME="focal"
      # We use focal ubuntu package for noble
      elif [ "${CODENAME}" = "noble" ]
      then
          CODENAME="focal"
      # We use buster debian package for trixie
      elif [ "${CODENAME}" = "trixie" ]
      then
          CODENAME="buster"
      fi
  elif command -v zypper >/dev/null 2>&1
  then
      PACKAGE_MANAGER=zypper
  elif command -v dnf >/dev/null 2>&1
  then
      PACKAGE_MANAGER=dnf
  elif command -v yum >/dev/null 2>&1
  then
      PACKAGE_MANAGER=yum
  else
      echo "Can't find compatible operating system"
      echo "Exit"
      exit 1
  fi

  # RHEL Family get OS major version (7, 8, 9)
  if [ "${PACKAGE_MANAGER}" = "yum" ] || [ "${PACKAGE_MANAGER}" = "dnf" ] || [ "${PACKAGE_MANAGER}" = "zypper" ]
  then
      if [ "${PACKAGE_MANAGER}" = "zypper" ]
      then
        CLEAN_PARAM="--"
      fi
      ${PACKAGE_MANAGER} clean ${CLEAN_PARAM:-}all > /dev/null
      OS_NAME="${ID}"
      OS_VERSION="${VERSION_ID}"
      OS_VERSION_MAJOR="${VERSION_ID%.*}"
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
      gnupg \
      certbot \
      wget \
      python3-certbot-nginx
  elif [ "${PACKAGE_MANAGER}" = "zypper" ]
  then
    # Adding a condition to differentiate openSUSE against SLES
    if [ "${ID}" = "sles" ] && [ "${VERSION_ID%.*}" = "15" ]
    then
      # If you are running the minimal image, you need to uncomment these commands
        # adding module web scripting repo and his dependency module server application for PHP
        # SUSEConnect --product sle-module-server-applications/15.6/x86_64
        # SUSEConnect --product sle-module-web-scripting/15.6/x86_64
        # download the prerequisites packages
        ${PACKAGE_MANAGER} --non-interactive install php8-fpm php8
        # create a default default php-fpm conf as it is required during the installer
        cp /etc/php8/fpm/php-fpm.conf /etc/php8/fpm/php-fpm.conf.default
    fi
    cat << EOF | tee /etc/zypp/repos.d/php.repo > /dev/null
[php]
enabled=1
autorefresh=0
baseurl=http://download.opensuse.org/repositories/devel:/languages:/php/openSUSE_Leap_${OS_VERSION}/
EOF
    PHP_EXTENSION_REPO_VERSION="${OS_VERSION}"
    if [ "${OS_VERSION}" = "15.4" ]
    then
      PHP_EXTENSION_REPO_VERSION="15.4"
    fi
    cat << EOF | tee /etc/zypp/repos.d/php-extensions-x86_64.repo > /dev/null
[php-extensions-x86_64]
enabled=1
autorefresh=0
baseurl=http://download.opensuse.org/repositories/server:/php:/extensions/${PHP_EXTENSION_REPO_VERSION}/
EOF
 elif [ "${OS_NAME}" = "fedora" ]
  then
    if ! rpm -qa | grep remi-release > /dev/null
    then
      ${PACKAGE_MANAGER} install -y https://rpms.remirepo.net/fedora/remi-release-"${OS_VERSION}".rpm
    fi
    ${PACKAGE_MANAGER} install -y dnf-plugins-core
    ${PACKAGE_MANAGER} module reset php -y
    ${PACKAGE_MANAGER} module install php:remi-8.1 -y
    ${PACKAGE_MANAGER} config-manager --set-enabled remi
    # pcre2 package needs to be upgraded to last version
    # there is a bug with preg_match() if we keep the current one installed
    ${PACKAGE_MANAGER} clean all
    ${PACKAGE_MANAGER} upgrade -y pcre2
  elif [ "${PACKAGE_MANAGER}" = "yum" ] || [ "${PACKAGE_MANAGER}" = "dnf" ]
  then
    ${PACKAGE_MANAGER} install -y wget python3
    
    # Install PHP 8.2 from AppStream
    ${PACKAGE_MANAGER} module -y reset php
    ${PACKAGE_MANAGER} module -y enable php:8.2
    ${PACKAGE_MANAGER} module -y install php:8.2
  fi
}

pull_updated_pub_key() {
  declare -a serverlist=("keys.openpgp.org" "keyserver.ubuntu.com")
  for serverin in "${serverlist[@]}"
  do
    if [ ! -d /root/.gnupg ]
    then
      mkdir -m 0700 /root/.gnupg
    fi
    # Handle gpg error in case of a server key failure
    # Without this check, and because we are using set -euo pipefail
    # The script fail in case of failure
    if curl -sS "https://${serverin}/pks/lookup?op=get&options=mr&search=0x${PASSBOLT_FINGERPRINT}" | gpg --dearmor --yes --output ${PASSBOLT_KEYRING_FILE}; then
      break
    fi
  done
}


setup_repository () {
  if [ "${PACKAGE_MANAGER}" = "apt" ]
  then
    pull_updated_pub_key > /dev/null
    chmod 644 ${PASSBOLT_KEYRING_FILE}

    cat << EOF | tee /etc/apt/sources.list.d/passbolt.sources > /dev/null
Types: deb
URIs: https://download.passbolt.com/${PASSBOLT_FLAVOUR}/${DISTRONAME}
Suites: ${CODENAME}
Components: ${PASSBOLT_BRANCH}
Signed-By: ${PASSBOLT_KEYRING_FILE}
EOF
    apt update
  elif [ "${OS_NAME}" = "fedora" ] || [ "${OS_VERSION_MAJOR}" -eq 9 ]
  then
    cat << EOF | tee /etc/yum.repos.d/passbolt.repo > /dev/null
[passbolt-server]
name=Passbolt Server
baseurl=https://download.passbolt.com/${PASSBOLT_FLAVOUR}/rpm/el8/${PASSBOLT_BRANCH}
enabled=1
gpgcheck=1
gpgkey=https://download.passbolt.com/pub.key
EOF
  elif [ "${PACKAGE_MANAGER}" = "zypper" ]
  then
    cat << EOF | tee /etc/zypp/repos.d/passbolt.repo > /dev/null
[passbolt-server]
name=Passbolt Server
baseurl=https://download.passbolt.com/${PASSBOLT_FLAVOUR}/rpm/opensuse/${PASSBOLT_BRANCH}
enabled=1
gpgcheck=1
gpgkey=https://download.passbolt.com/pub.key
EOF
elif [ "${PACKAGE_MANAGER}" = "yum" ] || [ "${PACKAGE_MANAGER}" = "dnf" ]
  then
    cat << EOF | tee /etc/yum.repos.d/passbolt.repo > /dev/null
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
    cat << EOF | tee /etc/yum.repos.d/mariadb.repo > /dev/null
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.4/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF
  fi
}

install_passbolt () {
    ${PACKAGE_MANAGER} install -y passbolt-${PASSBOLT_FLAVOUR}-server
}

setup_complete () {
  clear
  echo "ICAgICBfX19fICAgICAgICAgICAgICAgICAgX18gICAgICAgICAgX19fXwogICAgLyBfXyBcX19fXyAgX19fX18gX19fXy8gL18gIF9fX18gIC8gLyAvXwogICAvIC9fLyAvIF9fIGAvIF9fXy8gX19fLyBfXyBcLyBfXyBcLyAvIF9fLwogIC8gX19fXy8gL18vIChfXyAgfF9fICApIC9fLyAvIC9fLyAvIC8gLwogL18vICAgIFxfXyxfL19fX18vX19fXy9fLl9fXy9cX19fXy9fL1xfXy8KT3BlbiBzb3VyY2UgcGFzc3dvcmQgbWFuYWdlciBmb3IgdGVhbXMKLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLQoK" | base64 -d
  cat << EOF
passbolt repository setup is finished. You can now install passbolt ${PASSBOLT_FLAVOUR^^} edition with this command:

sudo ${PACKAGE_MANAGER} install passbolt-${PASSBOLT_FLAVOUR}-server
EOF
}

# Main
os_detect
compliance_check
install_dependencies
setup_repository
setup_complete
#install_passbolt