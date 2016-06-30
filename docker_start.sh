#!/bin/bash

service mysql start
sed -i -e "s/perl_exec_simple(\"setInterface\",\$Ri + \":\" + \$Rp);/perl_exec_simple(\"setInterface\",\"$hostname\" + \":\" + \"$port\");/g" /etc/kamailio/kamailio.cfg

/usr/sbin/kamailio -DD -P /var/run/kamailio.pid -f /etc/kamailio/kamailio.cfg
