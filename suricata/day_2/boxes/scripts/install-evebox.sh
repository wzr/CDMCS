#!/bin/bash
#
# this script:
# 1) installs evebox
#
#

if [ "$(id -u)" != "0" ]; then
   echo "ERROR - This script must be run as root" 1>&2
   exit 1
fi

ELASTIC=$1

IP=$(ifconfig eth0 2>/dev/null|grep 'inet addr'|cut -f2 -d':'|cut -f1 -d' ')
HOSTNAME=$(hostname -f)

echo "installing evebox on ${IP} ${HOSTNAME} sets elasticsearch to ${ELASTIC} ..."

apt-get -y install unzip
cd /opt/
wget -4 -q https://bintray.com/artifact/download/jasonish/evebox/evebox-linux-amd64.zip
unzip evebox-linux-amd64.zip
/opt/evebox-linux-amd64/evebox --version
echo "http.cors.enabled: true" >> /etc/elasticsearch/elasticsearch.yml
echo "http.cors.allow-origin: \"/.*/\"" >> /etc/elasticsearch/elasticsearch.yml
service elasticsearch restart

ln -s /opt/evebox-linux-amd64 /opt/evebox
ln -s /opt/evebox-linux-amd64/evebox /opt/evebox-linux-amd64/evebox-server
adduser --system evebox

cat > /etc/default/evebox-server <<DELIM
LOG_DIR=/var/log/evebox
DELIM

cat > /etc/init.d/evebox-server <<DELIM
#! /usr/bin/env bash

# chkconfig: 2345 80 05
# description: evebox server
# processname: evebox
# config: NONE
# pidfile: /var/run/evebox.pid

### BEGIN INIT INFO
# Provides:          evebox
# Required-Start:    $all
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start evebox at boot time
### END INIT INFO

# TODO
# ask ish to take this ownership

#  tested on
#  1. ubuntu 14.04

PATH=/bin:/usr/bin:/sbin:/usr/sbin
NAME=evebox-server
DESC="EveBox Server"
DEFAULT=/etc/default/$NAME

EVEBOX_USER=evebox
EVEBOX_GROUP=evebox
EVEBOX_HOME=/usr/share/evebox
CONF_DIR=/etc/evebox
WORK_DIR=$EVEBOX_HOME
DATA_DIR=/var/lib/evebox
LOG_DIR=/var/log/evebox
CONF_FILE=$CONF_DIR/evebox.ini
MAX_OPEN_FILES=10000
PID_FILE=/var/run/$NAME.pid
DAEMON=/opt/sbin/$NAME

umask 0027

if [ `id -u` -ne 0 ]; then
	echo "You need root privileges to run this script"
	exit 4
fi

if [ ! -x $DAEMON ]; then
  echo "Program not installed or not executable"
  exit 5
fi

. /lib/lsb/init-functions

if [ -r /etc/default/rcS ]; then
	. /etc/default/rcS
fi

# overwrite settings from default file
if [ -f "$DEFAULT" ]; then
	. "$DEFAULT"
fi

DAEMON_OPTS="--pidfile=${PID_FILE} --config=${CONF_FILE} cfg:default.paths.data=${DATA_DIR} cfg:default.paths.logs=${LOG_DIR}"

case "$1" in
  start)

	log_daemon_msg "Starting $DESC"

	pid=`pidofproc -p $PID_FILE evebox`
	if [ -n "$pid" ] ; then
		log_begin_msg "Already running."
		log_end_msg 0
		exit 0
	fi

	# Prepare environment
	mkdir -p "$LOG_DIR" "$DATA_DIR" && chown "$EVEBOX_USER":"$EVEBOX_GROUP" "$LOG_DIR" "$DATA_DIR"
	touch "$PID_FILE" && chown "$EVEBOX_USER":"$EVEBOX_GROUP" "$PID_FILE"

  if [ -n "$MAX_OPEN_FILES" ]; then
		ulimit -n $MAX_OPEN_FILES
	fi

	# Start Daemon
	start-stop-daemon --start -b --chdir "$WORK_DIR" --user "$EVEBOX_USER" -c "$EVEBOX_USER" --pidfile "$PID_FILE" --exec $DAEMON -- $DAEMON_OPTS
	return=$?
	if [ $return -eq 0 ]
	then
	  sleep 1

    # check if pid file has been written two
	  if ! [[ -s $PID_FILE ]]; then
	    log_end_msg 1
	    exit 1
	  fi

		i=0
		timeout=10
		# Wait for the process to be properly started before exiting
		until { cat "$PID_FILE" | xargs kill -0; } >/dev/null 2>&1
		do
			sleep 1
			i=$(($i + 1))
      if [ $i -gt $timeout ]; then
			  log_end_msg 1
			  exit 1
			fi
		done
  fi
  log_end_msg $return
	;;
  stop)
	log_daemon_msg "Stopping $DESC"

	if [ -f "$PID_FILE" ]; then
		start-stop-daemon --stop --pidfile "$PID_FILE" \
			--user "$EVEBOX_USER" \
			--retry=TERM/20/KILL/5 >/dev/null
		if [ $? -eq 1 ]; then
			log_progress_msg "$DESC is not running but pid file exists, cleaning up"
		elif [ $? -eq 3 ]; then
			PID="`cat $PID_FILE`"
			log_failure_msg "Failed to stop $DESC (pid $PID)"
			exit 1
		fi
		rm -f "$PID_FILE"
	else
		log_progress_msg "(not running)"
	fi
	log_end_msg 0
	;;
  status)
	status_of_proc -p $PID_FILE evebox evebox && exit 0 || exit $?
    ;;
  restart|force-reload)
	if [ -f "$PID_FILE" ]; then
		$0 stop
		sleep 1
	fi
	$0 start
	;;
  *)
	log_success_msg "Usage: $0 {start|stop|restart|force-reload|status}"
	exit 3
	;;
esac
DELIM
update-rc.d evebox-server defaults 95 10 > /dev/null 2>&1
