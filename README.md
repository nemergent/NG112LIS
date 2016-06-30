Nemergent LIS Server
=====================
* Author: Iñigo Ruiz Relloso
* Email:  iruizr7@gmail.com
* Copyright (c) 2016, Nemergent Initiative http://nemergent.com

This Location Information Server (LIS) was created in order fill the existing Open-Source gap around the new NG112 platform by EENA.
**Beware that this project is very experimental and is ONLY intended to work as a research reference for developing NG112 apps.
Security concerns and variable performance are expected and thus is definitely NOT advised to run it for production.**

We provide manual and automatic (Docker) installation instructions, being the Docker one the most stable/tested one.

How to install Nemergent LIS Server (Docker Version)
==============================

Simply execute:

    docker build -t nemergent/lis .
    docker run -itd -p 81:81 -p 5060:5060/udp --name LIS -e hostname=192.168.1.44 -e port=81  nemergent/lis

You need to set the hostname variable to the hostname/IP through which the LIS server can be accessed via HTTP, jut the same with the port.
If the suggested ports does not conform with your organization needs, you can change them, as below:

    docker run -itd -p 8081:81 -p 9060:5060/udp --name LIS -e hostname=192.168.1.44 -e port=8081  nemergent/lis

This hostname/IP is reported on the Location Dereference URLs.

How to install Nemergent LIS Server (Manual Version)
==============================

Requirements:

* Kamailio SIP Server
* A MySQL Server
* Kamailio's Perl, Presence and MySQL modules
* Perl's CBC Crypt, AES, DateTime and Try::Tiny modules

Procedure
---------
This howto will describe the steps to install the LIS server on Ubuntu 14.04 LTS 64 bits. Steps for the rest of the Ubuntu family should be similar, especially for the later versions.

### Install Kamailio, MySQL server and all the dependencies

    apt-get install \
    kamailio \
    kamailio-mysql-modules \
    kamailio-presence-modules \
    kamailio-perl-modules \
    libcrypt-cbc-perl \
    libdatetime-perl \
    libtry-tiny-perl \
    build-essential \
    libssl-dev \
    mysql-server \
    autoconf \
    libxml2-dev \
    libxml-parser-perl

Install the AES and LibXML modules from CPAN:

    cpan Crypt::OpenSSL::AES
    cpan XML::LibXML
    cpan -f -i XML::Tidy

Edit the config file `/etc/default/kamailio` and uncomment the lines dealing with the start, user, and group configuration for kamailio:

    # Set to yes to enable kamailio, once configured properly.
    RUN_KAMAILIO=yes

    # User to run as
    USER=kamailio

    # Group to run as
    GROUP=kamailio

Edit the config file `/etc/kamailio/kamctlrc` and uncomment the line dealing with the use of a MySQL engine:

    DBENGINE=MYSQL

Create the following folder for kamailio to store run information:

    mkdir -p /var/run/kamailio

Create the user for kamailio to run:  

    adduser --quiet --system --group --disabled-password \
    --shell /bin/false --gecos "Kamailio" \
    --home /var/run/kamailio kamailio

And give proper permissions:  

    chown kamailio:kamailio /var/run/kamailio

Copy the kamailio.cfg file to the default destination (`/etc/kamailio/kamailio.cfg`).

Copy the LIS.pl file to the Kamailio Perl folder `/usr/lib/x86_64-linux-gnu/kamailio/perl/`

Start MySQL (`service mysql start`) and run the `kamdbctl create` command and answer yes to all the questions.

To start kamailio just issue the following command:  

    kamctl start

To access Kamailio logs, just print the syslog

    tail -n 100 /var/log/syslog

### Publish presence using SIPP

#### Install SIPP

On Ubuntu:

    apt-get install sip-tester

Modify the PseudoVariables LOCALIP and LISADRESS in the `publish.sh` file.

Modify the `user-data.csv` file if you need to change some example data.
The format is `SIPURI;ALT;LONG;`

To execute the PUBLISH against the LIS Server, issue:

    ./publish.sh
