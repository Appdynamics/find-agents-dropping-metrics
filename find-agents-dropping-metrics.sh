#!/bin/bash

# Copyright 2018, AppDynamics LLC and its affiliates
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

STDERRFILE=/tmp/find-agents-dropping-metrics.stderr.log

DROPPED_METRICS_SIGNATURE="WARN MetricHandler - Metric Reporter Queue full. Dropping metrics."

USAGE="\
Command: find-agents-dropping-metrics.sh

Description:
Scans open agent.*.log files for messages containing,
'$DROPPED_METRICS_SIGNATURE'

If it finds any, it prints the PID and full command line for each process,
(one tuple per line), and exits with status code 0.

If it does not find any, it will exit with status code 1.

Exit status codes greater than 1 indicate a runtime error. See
$STDERRFILE
for further diagnostic information."

# handle -h and any misguided attempts to feed this script any args.
UNRECOGNIZED_ARG=false
while getopts ":h" OPTION; do
    case $OPTION in
        h)
            echo "$USAGE"
            exit 0
        ;;
        *)
            echo "Unrecognized argument: $OPTARG"
            UNRECOGNIZED_ARG=true
    esac
done

if $UNRECOGNIZED_ARG; then
    echo "$USAGE"
    exit 2
fi

if ! touch "$STDERRFILE"; then
    >&2 echo "\
ERROR: Unable to write to $STDERRFILE
Exiting."
    exit 3
fi

if [[ -z "$(which lsof)" ]]; then
    >&2 echo "ERROR: Required program 'lsof' not found in \$PATH;"
    exit 4
fi

# Redirect all STDERR output to $STDERRFILE
exec 2> "$STDERRFILE"

# lsof 2>/dev/null |  awk '/agent.[_0-9]*.[0-9]*.log/{pid=$2;if($10) logfile=$10;else logfile=$9; printf("%d %s\n", pid, logfile)}'

declare -a PID LOGFILE

# get open agent log files and their associated PIDs
eval `lsof 2>/dev/null |  awk '/agent.[_0-9]*.[0-9]*.log/{
    pid=$2;
    if($10){
        logfile=$10;
    }else{
        logfile=$9;
    }
    printf("%d %s\n", pid, logfile)
}' | sort -u | awk 'BEGIN{i=0}{
    printf("PID[%1$d]=%2$d; LOGFILE[%1$d]=\"%3$s\";\n", i, $1, substr($0, index($0, $2)));
    i++
}
'`

N_TUPLES=${#PID[@]}
if [ $N_TUPLES -eq 0 ]; then
    >&2 echo "ERROR: No open agent log files found."
    exit 5
else
    EXIT_STATUS=1
    i=0
    while [ $i -lt $N_TUPLES ]; do
        if grep -q "$DROPPED_METRICS_SIGNATURE" "${LOGFILE[$i]}"; then
            echo "${PID[$i]} $(ps -hp ${PID[$i]} -o command)"
            EXIT_STATUS=0
        fi
        ((i++))
    done
fi