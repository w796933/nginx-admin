#!/bin/sh
#
### BEGIN INIT INFO
# Provides:             nginx-admin
# Required-Start:       $remote_fs $network
# Required-Stop:        $remote_fs $network
# Should-Start:         $named
# Should-Stop:          $named
# Default-Start:        2 3 4 5
# Default-Stop:         0 1 6
# Short-Description:    Nginx Admin
# Description:          Provide Nginx Admin startup/shutdown script
### END INIT INFO

. /lib/lsb/init-functions

if [ `id -u` -ne 0 ]; then
	echo "You need root privileges to run this script"
	exit 1
fi

if [ -f "/etc/environment" ]; then
	. "/etc/environment"
fi

if [ -z "$NGINX_ADMIN_HOME" ]; then
	echo "You need set NGINX_ADMIN_HOME enviroment variable to run this script"
	exit 1
fi

. $NGINX_ADMIN_HOME/conf/nginx-admin.conf

NGINX_ADMIN_NAME=nginx-admin
NGINX_ADMIN_PIDFILE=/var/run/$NGINX_ADMIN_NAME/nginx-admin.pid
NGINX_ADMIN_CONSOLE_LOG=$NGINX_ADMIN_LOG/console.log
STARTUP_WAIT=30
SHUTDOWN_WAIT=30

pid_exists(){
	test -f $NGINX_ADMIN_PIDFILE
}

pid() {
    if pid_exists ; then
          echo $(cat $NGINX_ADMIN_PIDFILE)
    else
          echo 0
    fi
    return 0
}

is_running() {
    pidofproc -p "$NGINX_ADMIN_PIDFILE" "java" >/dev/null 2>&1
}

is_dead() {
    pid_exists && ! is_running
}


is_launched() {
	count=0
	until [ $count -gt $STARTUP_WAIT ]
	do
		sleep 1
		count=$((count+1))
		if is_running ; then
			return 0
		fi	
	done
	return 1
}

remove_db_lock() {
  NGINX_ADMIN_DB_LOCK_FILE="$NGINX_ADMIN_DB_LOCATION/$NGINX_ADMIN_DB_NAME.lock.db"
  if [ -f "$NGINX_ADMIN_DB_LOCK_FILE" ] ; then
    rm -f "$NGINX_ADMIN_DB_LOCK_FILE"
  fi
  return 0
}


try_launch() {
 	mkdir -p $(dirname $NGINX_ADMIN_PIDFILE)
    mkdir -p $(dirname $NGINX_ADMIN_CONSOLE_LOG)
    rm -f $NGINX_ADMIN_CONSOLE_LOG
    chown $NGINX_ADMIN_USER $(dirname $NGINX_ADMIN_PIDFILE) || true
    remove_db_lock

	start-stop-daemon --start --make-pidfile --pidfile $NGINX_ADMIN_PIDFILE --chuid $NGINX_ADMIN_USER --user $NGINX_ADMIN_USER --chdir $NGINX_ADMIN_HOME --exec $JAVA -- -server -Djava.net.preferIPv4Stack=true -Djava.awt.headless=true -Xms256m -Xmx1g -jar $NGINX_ADMIN_BIN/nginx-admin-ui-standalone-$NGINX_ADMIN_VERSION-swarm.jar -c $NGINX_ADMIN_CONF/nginx-admin.conf >> $NGINX_ADMIN_CONSOLE_LOG 2>&1 &
	
	if ! is_launched ; then
		rm -f $NGINX_ADMIN_PIDFILE
		exit_with_failure "$NGINX_ADMIN_NAME not started please see server log on $NGINX_ADMIN_CONSOLE_LOG for details and report issue on https://github.com/jslsolucoes/nginx-admin please"
	else
		exit_with_success "$NGINX_ADMIN_NAME is started"
	fi
}

start() {
	if is_running ; then
		exit_with_failure "$NGINX_ADMIN_NAME is already running"
	else
		try_launch
	fi
}

exit_with_success(){
	log_success_msg $1
	return 0
}

exit_with_failure(){
	log_failure_msg $1
	return 1
}

killpid() {
	start-stop-daemon --stop --quiet --pidfile $NGINX_ADMIN_PIDFILE --user $NGINX_ADMIN_USER --retry=TERM/$SHUTDOWN_WAIT/KILL/5 >/dev/null 2>&1
	children_pids=$(pgrep -P $(pid))
	for child in $children_pids; do
		/bin/kill -9 $child >/dev/null 2>&1
	done
	rm -f $NGINX_ADMIN_PIDFILE
}

stop() {
	if is_running ; then
		killpid
		exit_with_success "$NGINX_ADMIN_NAME is stopped"
	else 
		exit_with_failure "$NGINX_ADMIN_NAME is already stopped"
	fi	
}

status() {
	if is_running ; then
		exit_with_success "$NGINX_ADMIN_NAME is running (pid $(pid))" 
	elif is_dead ; then
		exit_with_failure "$NGINX_ADMIN_NAME is dead but pid file exists"
	else
		exit_with_failure "$NGINX_ADMIN_NAME is not running"
	fi
}

case "$1" in
	start)
		start
		;;
	stop)
		stop
		;;
	restart)
		$0 stop
		$0 start
		;;
	status)
		status
		;;
	*)
		
	log_action_msg "Usage: $0 {start|stop|status|restart}"
	exit 1
	;;
esac
