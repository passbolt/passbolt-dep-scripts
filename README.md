
	      ____                  __          ____
	     / __ \____  _____ ____/ /_  ____  / / /_
	    / /_/ / __ `/ ___/ ___/ __ \/ __ \/ / __/
	   / ____/ /_/ (__  |__  ) /_/ / /_/ / / /_
	  /_/    \__,_/____/____/_,___/\____/_/\__/
	
	The open-source password management solution for teams
	(c) 2022 Passbolt SA
	https://www.passbolt.com

## License

Passbolt - Open source password manager for teams
(c) 2022 Passbolt SA

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General 
Public License (AGPL) as published by the Free Software Foundation version 3.

The name "Passbolt" is a registered trademark of Passbolt SA, and Passbolt SA hereby declines to grant a trademark 
license to "Passbolt" pursuant to the GNU Affero General Public License version 3 Section 7(e), without a separate 
agreement with Passbolt SA.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied 
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License along with this program. If not, see GNU 
Affero General Public License v3.

## About Passbolt dependencies scripts repository

This repository contains bash scripts to configure a vanilla Linux server in order to setup passbolt CE/PRO with Linux package.

## Workflow

### Operating system detection

This script has been reported to work on the following operating systems:

* Debian 10 / 11
* Raspbian (Raspberry Pi)
* Ubuntu 20.04 / 22.04
* CentOS 7
* Red Hat 7 / 8
* RockyLinux 8
* AlmaLinux 8
* Oracle Linux 8
* OpenSUSE 15
* Fedora 34 / 35 / 36

### System checks

* IPv6 support
* No PHP installed
* RPM: no `remi-release` package installed

### Dependencies installation

* Certbot
* gnupg
* PHP repository setup for RPM

### passbolt repository setup

Finally, script configure passbolt repository to install the passbolt Linux package.