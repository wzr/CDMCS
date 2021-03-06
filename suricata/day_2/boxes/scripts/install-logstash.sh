#!/bin/bash
#
# this script:
# 1) installs logstash
# 2) sets elastic to $1 in conf.d/suricata.conf
#

if [ "$(id -u)" != "0" ]; then
   echo "ERROR - This script must be run as root" 1>&2
   exit 1
fi
IP=$(ifconfig eth0 2>/dev/null|grep 'inet addr'|cut -f2 -d':'|cut -f1 -d' ')
HOSTNAME=$(hostname -f)
ELASTIC=$1
echo "installing logstash on $IP $HOSTNAME setting elasticsearch on $ELASTIC"

#ELASTIC=$(ifconfig eth0 2>/dev/null|grep 'inet addr'|cut -f2 -d':'|cut -f1 -d' ')
echo 'deb http://packages.elasticsearch.org/logstash/2.2/debian stable main' > /etc/apt/sources.list.d/logstash.list
apt-get update > /dev/null 2>&1
apt-get -y --force-yes install logstash > /dev/null 2>&1
#stealing amsterdam losgstash conf
wget -4 -q https://raw.githubusercontent.com/StamusNetworks/Amsterdam/master/src/config/logstash/conf.d/logstash.conf -O /etc/logstash/conf.d/suricata.conf
#    hosts => elasticsearch
sed -i -e 's,hosts => elasticsearch,hosts => "'${ELASTIC}'"\n index => "logstash-%{+YYYY.MM.dd.HH}",g' /etc/logstash/conf.d/suricata.conf
#fix this hack
chmod 777 /var/log/suricata/eve.json
service logstash start > /dev/null 2>&1
cat > /etc/telegraf/telegraf.d/logstash.conf <<DELIM
[[inputs.procstat]]
  pid_file = "/var/run/logstash.pid"
DELIM
service telegraf restart > /dev/null 2>&1
