# -*- coding: utf-8 -*-
# Create: 07.12.2020
# Author: nothingctrl (nothingctrl@gmail.com)
# ---------------------------------------------------------------------------------------------------------------------
# Detect mail server (Zimbra) inject by miner virus name `kinsing`
# this virus use all CPU resource and have some behaviour:
#   - Create a crontab as zimbra to download .sh script using wget
#   - Download / create execute file in /var/tmp, /tmp, /opt/zimbra/log/
#   - Run process with name: `kinsing...`, `kdevtmpfsi...`
#   - In log file `/opt/zimbra/log/zmmailboxd.out`, every time virus file create, have a log: `/opt/zimbra/log/kinsing...`
#
# ---------------------------------------------------------------------------------------------------------------------
# We has try secure memchached service only listen on 127.0.0.1,
# remove some non-use ip from `zimbraHttpThrottleSafeIPs`
#
# This file attempt to auto detect virus process if it running and kill it
# this file should run as root user

import subprocess
import os
import logging
import signal
import time
from urllib import request, parse
from logging.handlers import RotatingFileHandler

base_dir = os.path.dirname(os.path.realpath(__file__))
base_name = os.path.basename(os.path.realpath(__file__))

def init_logger():
    new_logger = logging.getLogger()
    new_logger.setLevel(logging.INFO)

    formatter = logging.Formatter('%(asctime)s,%(msecs)d %(name)s %(levelname)s %(message)s')
    file_handler = RotatingFileHandler(os.path.join(base_dir, '{}.log'.format(base_name)), mode='a', maxBytes=2048000,
                                       backupCount=1, encoding='utf-8')
    file_handler.setLevel(logging.INFO)
    file_handler.setFormatter(formatter)
    new_logger.addHandler(file_handler)
    return new_logger

def ps_cmd_value_format(string: str):
    keys = ['uid', 'pid', 'ppid', 'c', 'stime', 'tty', 'time', 'cmd']
    values = {}
    value = ''
    key = keys.pop(0)
    for i in range(0, len(string)):
        if string[i] == ' ':
            if key == 'cmd':
                if key not in values:
                    values[key] = string[i]
                else:
                    values[key] += string[i]
            elif value:
                values[key] = value
                value = ''
                key = keys.pop(0)
        else:
            if key == 'cmd':
                if key not in values:
                    values[key] = string[i]
                else:
                    values[key] += string[i]
            else:
                value += string[i]
    return values

def delete_files(name_contains: list, scan_in_dirs: list):
    to_remove_files = []
    removed_files = []
    for p in scan_in_dirs:
        if os.path.isdir(p):
            items = os.listdir(p)
            for _name in items:
                _path = os.path.join(p, _name)
                if os.path.isfile(_path):
                    for _np in name_contains:
                        if _np in _name:
                            to_remove_files.append(_path)
                            break
    for item in to_remove_files:
        try:
            os.unlink(item)
            removed_files.append(item)
        except:
            pass
    return to_remove_files, removed_files


if __name__ == '__main__':
    _logger = init_logger()
    process_kins_pre = './kinsing'
    process_kdev_pre = '/tmp/kdevtmpfsi'
    while True:
        try:
            _logger.info("Checking for miner process")
            result = subprocess.run(['ps', '-ef'], stdout=subprocess.PIPE)
            output = result.stdout.decode('utf-8')  # output have multi-line, each with 8 cols: UID, PID, PPID, C, STIME, TTY, TIME, CMD
            if process_kins_pre in output or process_kdev_pre in output:
                _logger.info("Miner detect!")
                output = output.splitlines()
                kins_pids = []
                kdev_pids = []
                for item in output:
                    if process_kins_pre in item or process_kdev_pre in item:
                        ps_data = ps_cmd_value_format(item)
                        if ps_data:
                            if process_kins_pre in item:
                                kins_pids.append(int(ps_data['pid']))
                            if process_kdev_pre in item:
                                kdev_pids.append(int(ps_data['pid']))
                _logger.info("PIDs kinsing: {}".format(str(kins_pids)))
                _logger.info("PIDs kdevtmpfsi: {}".format(str(kdev_pids)))
                _logger.info("Kill miner process...")
                try:
                    for kid in kins_pids:
                        os.kill(kid, signal.SIGKILL)
                    for kid in kdev_pids:
                        os.kill(kid, signal.SIGKILL)
                except:
                    pass
                # delete miner virus files
                to_delete, deleted = delete_files(['kinsing', 'kdevtmpfsi'], ['/var/tmp', '/tmp', '/opt/zimbra/log'])
                _logger.info("- Virus files to delete: {}".format(", ".join(to_delete)))
                _logger.info("- Virus files success delete: {}".format(", ".join(deleted)))
                recheck = subprocess.run(['ps', '-ef'], stdout=subprocess.PIPE)
                output = recheck.stdout.decode('utf-8')
                if process_kins_pre not in output and process_kdev_pre not in output:
                    _logger.info("Kill success")
                else:
                    _logger.warning("Kill failed, miner process still exist!")
            else:
                _logger.info("OK")
        except Exception as e:
            _logger.error("Error: {}".format(str(e)))
        time.sleep(15)
