#!/bin/sh
# $Id: sendmailctl.SH,v 5.43 2008/02/28 06:16:16 ak Exp $
# @(#) sendmailctl(8) - The control interface of sendmail-virtualmailbox
#                     _                 _ _      _   _ 
#  ___  ___ _ __   __| |_ __ ___   __ _(_) | ___| |_| |
# / __|/ _ \ '_ \ / _` | '_ ` _ \ / _` | | |/ __| __| |
# \__ \  __/ | | | (_| | | | | | | (_| | | | (__| |_| |
# |___/\___|_| |_|\__,_|_| |_| |_|\__,_|_|_|\___|\__|_|
#
readonly SYSVERSION='__SYSVERSION__'
readonly SMUSER='__SENDMAILUSER__'
readonly MYNAME="`basename $0`"

KILL_SIGNAL=15
DEBUG_LEVEL=''
SMLOG_LEVEL=''
RUN_MAKEMAP='0'
STDERRORDEV='/dev/stderr'
STATUS_CODE=1
CHAR_OK='[ OK ]'
CHAR_NG='[FAIL]'
CHAR_WARN='[WARN]'
CHAR_INFO='[INFO]'
CHAR_SKIP='[SKIP]'

# * Error or exit status code. see sysexits.h
EX_OK=0		# operation completed successfully
EX_GENERAL=1	# generic error
EX_USAGE=64	# invalid gesogram option or argument
EX_SOFTWARE=70	# internal software error
EX_OSERR=71	# system error
EX_OSFILE=72	# critical OS file missing
EX_CONFIG=78	# gesogram config | environment error
EX_NOPERM=77	# permission denied


smcontrol()
{
	local whataction=$1
	local procidfile='/var/run/sendmail.pid'

	if [ "${whataction}X" = "startX" ]; then

		msg 'Starting sendmail ... '
		if [ -s "$procidfile" ]; then
			msg ", $procidfile exists"
			result NG
			STATUS_CODE=$EX_GENERAL
		else
			local mtaoptions=''
			local daemonopts="`test -s /etc/mail/daemon-options && grep -v '^#' /etc/mail/daemon-options`"
			local mqinterval="`test -s /etc/mail/queue-interval && head -1 /etc/mail/queue-interval`"

			[ -n "$SMLOG_LEVEL" ] && mtaoptions="$mtaoptions -OLogLevel=$SMLOG_LEVEL"
			[ -n "$DEBUG_LEVEL" ] && mtaoptions="$mtaoptions -d$DEBUG_LEVEL"

			[ -z "$mqinterval" ] && mqinterval='6m'
			( /usr/sbin/sendmail -bd -q$mqinterval $daemonopts $mtaoptions && sleep 1 )

			if [ "$?" -eq "0" -a -s "$procidfile" ]; then
				result OK
				STATUS_CODE=$EX_OK
			else
				result NG
				STATUS_CODE=$EX_GENERAL
			fi
		fi

	elif [ "${whataction}X" = "stopX" ]; then

		msg 'Stopping sendmail ... '
		if [ -s "$procidfile" ]; then
			( kill -$KILL_SIGNAL `head -1 $procidfile` && sleep 1 )
			if [ "$?" -eq "0" -a ! -s "$procidfile" ]; then
				result OK
				STATUS_CODE=$EX_OK
			else
				result NG
				STATUS_CODE=$EX_GENERAL
			fi
		else
			msg ", $procidfile does not exist"
			result NG
			STATUS_CODE=$EX_GENERAL
		fi
	fi
}

makemaps()
{
	for M in access genericstable virtusertable mailertable authinfo; do
		msg "makemap $M.db ... "
		if [ -f "/etc/mail/$M" ]; then
			/usr/sbin/makemap hash /etc/mail/$M.db < /etc/mail/$M > /dev/null 2>&1
			if [ "$?" -eq "0" ]; then
				result OK
				STATUS_CODE=$EX_OK
			else
				result NG
				STATUS_CODE=$EX_GENERAL
			fi
		else
			msg ', map does not exist'
			result SKIP
		fi
	done
}

makealiases()
{
	msg 'Running newaliases ... '
	if [ -f "/etc/mail/aliases" ]; then
		msg ", build /etc/mail/aliases"
		/usr/sbin/sendmail -bi > /dev/null 2>&1
		if [ "$?" -eq "0" ]; then
			chown root.$SMUSER /etc/mail/aliases.db
			chmod 0640 /etc/mail/alases.db
			result OK
			STATUS_CODE=$EX_OK
		else
			result NG
			STATUS_CODE=$EX_GENERAL
		fi
	else
		result NG
		STATUS_CODE=$EX_OSFILE
	fi
}

printqueues()
{
	queueswitch="$1"
	sendmailcmd="/usr/sbin/sendmail"
	case $queueswitch in
		L)
			$sendmailcmd -bp -qL -v
			;;

		Q|Quarantine)
			if [ "${queueswitch}X" = "QuarantineX" ]; then
				$sendmailcmd -bp -v -qQpostsend -OQueueSortOrder=none -OMaxQueueRunSize=1
			else
				$sendmailcmd -bp -v -qQpostsend -OQueueSortOrder=none -OMaxQueueRunSize=1 \
					| grep -i 'Total' | sed 's|^.*requests\?: ||i'
			fi
			;;

		q)
			$sendmailcmd -bp -OMaxQueueRunSize=1 -OQueueSortOrder=none \
				| grep -i 'Total' | sed 's|^.*requests\?: ||i'
			;;
		queue)
			$sendmailcmd -bp -OQueueSortOrder=none
			;;
	esac
}

sendmailstatus()
{
	local procidfile="/var/run/sendmail.pid"
	if [ -f "$procidfile" ]; then
		msg "sendmail is running, pid = `head -n 1 $procidfile`"
		echo > $STDERRORDEV
		msg "command args = `tail -n 1 $procidfile`"
		echo > $STDERRORDEV
	fi
}

proclist()
{
	ps axuww | grep sendmail: | grep -v grep | sed 's| *$||g'
}

msg()
{
	[ "${TERM}X" = "X" ] && STDERRORDEV='/dev/null'
	echo -n "$1" > $STDERRORDEV
}

cleandirtyqueus()
{
	# Clean up dirty queues.
	local date_expire=1
	local queue_names=''
	local queue_spool="/var/spool/queues"

	# Delete fake queues
	queue_names=`find $queue_spool -type f \
		-name "[A-Z]f??????????????" -exec basename {} \; | sed 's|^..||g' | sort | uniq`

	if [ -n "$queue_names" ]; then
		for qn in $queue_names; do
			find $queue_spool -type f -name "[Qdlntxq]f$qn" -delete
		done
	fi

	# Delete expired queues
	find $queue_spool -type f -atime +$date_expire -name "[A-Za-z]f??????????????" -delete
}

result()
{
	local msgtype="$1"
	local message=''
	[ "${TERM}X" = "X" ] && STDERRORDEV='/dev/null'

	case "$msgtype" in
		ok|OK)
			message=$CHAR_OK
			;;

		ng|NG)
			message=$CHAR_NG
			;;

		warn|WARN)
			message=$CHAR_WARN
			;;

		info|INFO)
			message=$CHAR_INFO
			;;

		skip|SKIP)
			message=$CHAR_SKIP
			;;
		*)
			;;
	esac

	printf \\033[70G > $STDERRORDEV
	printf \\033[1\;49m > $STDERRORDEV
	echo -n $message > $STDERRORDEV
	printf \\033[0\;39m > $STDERRORDEV
	echo > $STDERRORDEV
}

init()
{
	export PATH='/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin'
	export LANG='C'
	if [ -x "/usr/sbin/sendmail" ]; then 
		:
	else
		echo "Cannot execute /usr/sbin/sendmail" > $STDERRORDEV
		exit $EX_GENERAL
	fi
}

help()
{
	echo
	echo 'usage:'
	echo " $MYNAME [ OPTION [ARGV] ] COMMAND"
	echo
	echo '  COMMAND:'
	echo '     start        : Start sendmail daemon.'
	echo '     stop         : Stop sendmail.'
	echo '     restart      : Restart ( stop & start )'
	echo '     status,s     : Print sendmail status, content of pid file.'
	echo '     mailq        : Print the detail of mail queue.'
	echo '     newaliases   : Run newaliases command.'
	echo '     queue,q      : Print the number of mail queues.'
	echo '     ps           : Print sendmail processes.'
	echo '     clean        : Clean up dirty queues and dirty processes( sendmail should be stopped ).'
	echo '     help,h       : Print this screen. '
	echo 

	echo '  OPTIONS:'
	echo '   * boot options:'
	echo '     -d <n|KEY>   : Enable debug mode (-d<n>) and output transwhataction logs'
	echo '     -L <n>       : Specify LogLevel'
	echo '     -M           : Run makemap before starting.'
	echo "     -v           : Print $MYNAME/sendmail version"
	echo

	if [ $ENABLE_DEBUG -eq 1 ]; then
		echo '  KEY: ( debug mode )'
		echo '    agent alias check class database error header io'
		echo '    macro mailer mci option queue ruleset syslog '
		echo
		echo '  ENVIRONMENT:'
		echo '   sendmail-8.14.0 or later required'
		echo
	fi
}

init
while getopts ":d:L:Mv" opt; do
	case $opt in
		d)
			# Enable debug mode
			case "$OPTARG" in
				agent|mailer)
					DEBUG_LEVEL='11.2'
					;;
				alias)
					DEBUG_LEVEL='27.1'
					;;
				check)
					DEBUG_LEVEL='48.2'
					;;
				class)
					DEBUG_LEVEL='37.8'
					;;
				database)
					DEBUG_LEVEL='38.20'
					;;
				error)
					DEBUG_LEVEL='6.1'
					;;
				header)
					DEBUG_LEVEL='31.10'
					;;
				io)
					DEBUG_LEVEL='58.20'
					;;
				macro)
					DEBUG_LEVEL='35.13'
					;;
				mci)
					DEBUG_LEVEL='42.20'
					;;
				option)
					DEBUG_LEVEL='37.1'
					;;
				quarantine)
					DEBUG_LEVEL='70.1'
					;;
				queue)
					DEBUG_LEVEL='41.1'
					;;
				ruleset)
					DEBUG_LEVEL='21.12'
					;;
				syslog)
					DEBUG_LEVEL='0.0'
					;;
				*)
					DEBUG_LEVEL="$OPTARG"
					;;
			esac

			ENABLE_DEBUG=1
			;;

		L)
			# Specify LogLevel option(external only)
			[ -n "$OPTARG" ] && SMLOG_LEVEL="$OPTARG"
			;;
		M)
			# Run makemap command when boot
			RUN_MAKEMAP=1
			;;
		v)
			# Print my version.
			SM_VERSION="`/usr/sbin/sendmail -d0.101 root < /dev/null 2> /dev/null | awk '{print $2}'`"
			echo -n "$SYSVERSION"
			test -n "$SM_VERSION" && echo -n "/$SM_VERSION"
			echo
			exit $EX_OK
			;;
		\?|*)
			;;
	esac
done

shift $( expr $OPTIND - 1 )


#  ____ ____ ____ ____ 
# ||m |||a |||i |||n ||
# ||__|||__|||__|||__||
# |/__`|/__`|/__`|/__`|
#
case "$1" in
	#  ____ ____ ____ _________ ____ ____ ____ ____ ____ ____ ____ ____ 
	# ||s |||u |||b |||       |||c |||o |||m |||m |||a |||n |||d |||s ||
	# ||__|||__|||__|||_______|||__|||__|||__|||__|||__|||__|||__|||__||
	# |/__`|/__`|/__`|/_______`|/__`|/__`|/__`|/__`|/__`|/__`|/__`|/__`|
	#
	clean)
		cleandirtyqueus
		;;

	help|h)
		help
		exit $EX_OK
		;;

	mailq)
		# Print the number of mail queues.
		# Compatible with the sendmail 8.11 ( no queue groups )
		printqueues mailq
		exit $EX_OK
		;;

	ps)
		# Print processes.
		proclist
		exit $EX_OK
		;;

	queue|q)
		# Print the number of mail queues.
		printqueues $1
		exit $EX_OK
		;;
	
	newaliases)
		# sendmail -bi
		makealiases
		exit $STATUS_CODE
		;;

	restart)
		smcontrol stop
		[ "$RUN_MAKEMAP" -eq "1" ] && makemaps
		smcontrol start
		;;

	start)
		[ "$RUN_MAKEMAP" -eq "1" ] && makemaps
		smcontrol start
		;;

	status|s)
		sendmailstatus
		;;

	stop|abort)
		if [ "$1" = "abort" ]; then
			KILL_SIGNAL=9	
		fi
		smcontrol stop
		;;
	
	*)
		echo "try $MYNAME help"
		exit $EX_USAGE
		;;
esac

