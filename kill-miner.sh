#!/bin/bash

# Variable definitions
#
# recipient - e-mail address that notifications are sent to
# sender - e-mail address that notifications are sent from (can be same as recipient if desired)
# user_id - string to hold the UID(s) of the suspect process(es)
# arr_user_id - string array to handle occurrence of multiple UIDs
# user_id_single - string variable to hold the current UID being processed
# miner_pid - string to hold the PID(s) of the suspect process(es)
# arr_miner_pid - string array to handle the occurrence of multiple PIDs
# miner_pid_single - string variable to hold the current PID being processed
# pid_binary_path - string to hold the absolute path of the executable tied to miner_pid_single
# pid_directory_path - string to hold the directory path containing the executable tied to miner_pid_single
# binary_names - string to hold the search pattern to use
# bad_sites - string to hold the domains known to be bad

# notification e-mail address
recipient="abuse@yourcompany.com"

# sender e-mail address
sender="root@server.yourcompany.com"

# binary names to hunt for
# add additional binary names to this string as they are found
binary_names="(kernelupdates)|(kernelcfg)|(kernelorg)|(kernelupgrade)|(named)"

# look for all UID running miner processes
user_id=`ps -ef | egrep $binary_names | grep -v grep | awk '{print $1}'`

# put UIDs in an array to account for multiple broken accounts
arr_user_id=($user_id)

# check to see if the array of user id's is empty
if [ ${#arr_user_id[@]} = 0 ]; then
    echo "First heuristic found no processes"
    exit 0
else
    echo "Notice: Suspect process found, investigating..."
    # process each UID found
    for user_id_single in "${arr_user_id[@]}"
    do
        # get the PID of the process in this iteration of the loop
        miner_pid=`ps -ef | grep ${user_id_single} | egrep $binary_names | awk '{print $2}'`
        arr_miner_pid=($miner_pid)
        if [ ! ${#arr_miner_pid[@]} = 0 ]; then
            for miner_pid_single in "${arr_miner_pid[@]}"
            do
                # look up and populate the path to the process binary
                pid_binary_path=`ls -l /proc/${miner_pid_single}/exe | awk '{print $11}'`
                pid_directory_path=`ls -l /proc/${miner_pid_single}/exe | awk '{print $11}' | sed "s/\/[^\/]*$//"`

                # try to kill the process
                if kill -9 $miner_pid_single; then
                    echo "Notice: Mining process ${miner_pid_single} killed."
                else
                    echo "Error: Attempt to kill process ${miner_pid_single} failed."
                fi

                # try to remove the binary of the PID
                if rm -rf ${pid_binary_path}; then
                    echo "Notice: Mining binary ${pid_binary_path} removed."
                else
                    echo "Error: Attempt to remove mining binary ${pid_binary_path} failed."
                fi

                # look for existence of mining tarball
                # if found attempt removal
                if [ -f ${pid_directory_path}/32.tar.gz ]; then
                    echo "Notice: Tarball found"
                    if rm -rf ${pid_directory_path}/32.tar.gz; then
                        echo "Notice: Tarball ${pid_directory_path}/32.tar.gz removed."
                    else
                        echo "Error: Attempt to remove tarball ${pid_directory_path}/32.tar.gz failed."
                    fi
                else
                    echo "Notice: Tarball not found."
                fi
            done
        fi

        # create and send email then clean up
        date > /tmp/miner.out
        echo "" >> /tmp/miner.out
        echo "User ID: ${user_id_single} was found to be running mining process" >> /tmp/miner.out
        echo "" >> /tmp/miner.out
        echo "Process was ${miner_pid_single}" >> /tmp/miner.out
        echo "" >> /tmp/miner.out
        echo "Process was running in: ${pid_directory_path}" >> /tmp/miner.out
        echo "" >> /tmp/miner.out
        echo "Files were removed and process was killed" >> /tmp/miner.out
        echo "" >> /tmp/miner.out
        echo "Please suspend user ${user_id_single}" >> /tmp/miner.out
        cat /tmp/miner.out | mail -s "Miner process found on lnh-sshftp1a" $recipient -- -f $sender
        rm /tmp/miner.out

        echo ${user_id_single}
    done
fi

# sites determined as bad
bad_sites="(updates.dyndn-web)|(updates.dyndn-web.com)"

# look for all UID running wget to the established suspect site(s) processes
user_id=`ps -ef | grep -i wget | egrep -i $bad_sites  | grep -v grep | awk '{print $1}' | sort -u`

# put UIDs in an array to account for multiple broken accounts
arr_user_id=($user_id)

# check to see if the array of user id's is empty
if [ ${#arr_user_id[@]} = 0 ]; then
  echo "Second heuristic found no processes"
  exit 0
else
  echo "Notice: Suspect process found, investigating..."

  # kill each of the wget processes
  ps -ef | grep wget | grep updates.dyndn-web | grep -v grep | awk '{print $2}' | xargs kill -9

  # sanitize the user crontab
  echo "Sanitizing user crontabs"
  for user_id_single in "${arr_user_id[@]}"
  do
    sed -i '/updates.dyndn-web/d' /var/spool/cron/${user_id_single}

    # create and send email then clean up
    date > /tmp/miner.out
    echo "" >> /tmp/miner.out
    echo "User ID: ${user_id_single} was found to be running mining process" >> /tmp/miner.out
    echo "" >> /tmp/miner.out
    echo "Crontab for user ${user_id_single} was sanitized and process was killed" >> /tmp/miner.out
    echo "" >> /tmp/miner.out
    echo "Please suspend user ${user_id_single}" >> /tmp/miner.out
    cat /tmp/miner.out | mail -s "Miner process found on lnh-sshftp1a" ${recipient} -- -f ${sender}
    rm /tmp/miner.out

    # return the user id for account suspension
    echo ${user_id_single}
  done
fi
