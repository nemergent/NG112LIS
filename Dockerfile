FROM ubuntu
MAINTAINER Iñigo Ruiz (Nemergent) <iruizr7@gmail.com>

RUN export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get upgrade -y && \
	apt-get install -y kamailio kamailio-mysql-modules kamailio-presence-modules kamailio-perl-modules \
	libcrypt-cbc-perl libdatetime-perl libtry-tiny-perl build-essential libssl-dev mysql-server autoconf libxml2-dev \
	libxml-parser-perl

RUN sed -i -e 's/# DBENGINE=MYSQL/DBENGINE=MYSQL/' /etc/kamailio/kamctlrc && \
	sed -i -e 's/#RUN_KAMAILIO=yes */RUN_KAMAILIO=yes/' /etc/default/kamailio

RUN mkdir -p /var/run/kamailio && \
	adduser --quiet --system --group --disabled-password --shell /bin/false --gecos "Kamailio" --home /var/run/kamailio kamailio && \
	chown kamailio:kamailio /var/run/kamailio

RUN cpan Crypt::OpenSSL::AES && cpan XML::LibXML && cpan -f -i XML::Tidy

WORKDIR /root

ADD kamailio.cfg LIS.pl docker_start.sh ./

RUN cp kamailio.cfg /etc/kamailio/kamailio.cfg && cp LIS.pl /usr/lib/x86_64-linux-gnu/kamailio/perl/ && \
	chmod +x docker_start.sh

RUN sed -i -e 's@ANSWER=${ANSWER/N/n}@ANSWER="y"@' /usr/lib/x86_64-linux-gnu/kamailio/kamctl/kamdbctl.base && \
	sed -i -e 's/#PW=""/PW=""/' /usr/lib/x86_64-linux-gnu/kamailio/kamctl/kamdbctl.mysql && \
	sed -i -e 's/prompt_pw$/:/' /usr/lib/x86_64-linux-gnu/kamailio/kamctl/kamdbctl.mysql && \
	service mysql start && kamdbctl create

CMD ["/bin/bash","docker_start.sh"]
