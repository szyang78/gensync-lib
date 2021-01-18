#!/usr/bin/env bash
#
# Author: Novak Boškov <boskov@bu.edu>
# Date: Jan, 2021.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

set -e

############################### PARAMETERS BEGIN ###############################
# how many times to repeat the same experiment
repeat=10

# CPISync related parameters files
server_params_file=server_params_data.cpisync
client_params_file=client_params_data.cpisync

# network parameters
latency=20
bandwidth=50
packet_loss=2
cpu_server=30
cpu_client=30

# where to obtain needed executables
mininet_path=~/Desktop/playground/mininet_exec/mininet_exec.py
python_path=~/.virtualenvs/statistics/bin/python
benchmarks_path=~/Desktop/CODE/cpisync/build/Benchmarks
################################ PARAMETERS END ################################

help() {
    echo -e "USAGE: ./run_experiments.sh [-q] [-r REMOTE_PATH]\n"
    echo -e "If remote machine is used, it needs Mininet and all the CPISync dependencies.\n"
    echo "OPTIONS:"
    echo "    -r REMOTE_PATH the path on remote to copy all the needed parts."
    echo "    -q when this script is run on remote set this."
    echo -e "\nEXAMPLES:"
    echo "    ./run_experiments.sh # runs locally"
    echo "    ./run_experiments.sh -r remote_name:/remote/path"
}

while getopts "r:qh" option; do
    case $option in
        r) remote_path=$OPTARG

           if ! [[ $benchmarks_path == *"build"* ]]; then
               echo "benchmark_path not in cpisync/build, cannot infer cpisync path from it."
               exit 1
           fi

           cpisync_dir="$(cd $(dirname $benchmarks_path); cd ..; pwd)"

           address_and_path=(${remote_path//:/ })
           address=${address_and_path[0]}
           path=${address_and_path[1]}

           ssh $address mkdir -p $path

           # Put CPISync source code on remote
           rsync -a --info=progress2   \
                 --exclude build       \
                 --exclude scripts     \
                 --exclude '.*'        \
                 --exclude *.deb       \
                 --exclude *.rpm       \
                 $cpisync_dir $remote_path

           # Build CPISync on remote
           ssh $address "cd $path/cpisync
                         mkdir build && cd build
                         cmake -GNinja . ../
                         ninja"

           rsync -a --info=progress2 \
                 $mininet_path $remote_path/$(basename $mininet_path)
           rsync -a --info=progress2 \
                 count_common.py $remote_path/count_common.py
           rsync -a --info=progress2 \
                 $server_params_file $remote_path/$(basename $server_params_file)
           rsync -a --info=progress2 \
                 $client_params_file $remote_path/$(basename $client_params_file)
           rsync -a --info=progress2 \
                 $(basename $0) $remote_path/$(basename $0)

           ssh -t $address "cd $path
                            timestamp=\$(date +%s)
                            nohup ./$(basename $0) -q > nohup_\$timestamp.out &
                            echo \"~~~~~~~~> nohup.out:\"
                            tail -f -n 1 nohup_\$timestamp.out"
           exit
           ;;
        # When run on remote, all the needed parts are in the same directory
        q) server_params_file=$(basename $server_params_file)
           client_params_file=$(basename $client_params_file)
           mininet_path=$(basename $mininet_path)
           pwd
           benchmarks_path=./cpisync/build/$(basename $benchmarks_path)
           ;;
        h|*) help
             exit
    esac
done

if ! [[ -f $mininet_path ]]; then
    echo "Mininet path does not exist: $mininet_path"
    exit 1
fi
if ! [[ -f $python_path ]]; then
    echo "Python path does not exist: $python_path"
    exit 1
fi
if ! [[ -f $benchmarks_path ]]; then
    echo -e "Benchmark executable does not exist: $benchmarks_path"
    exit 1
fi
if ! [[ -f $server_params_file ]]; then
    echo "No file: $server_params_file"
    exit 1
fi
if ! [[ -f $client_params_file ]]; then
    echo "No file: $client_params_file"
    exit 1
fi

# Cleanup Mininet environment
sudo mn -c

# reset log directories
rm -rf '.cpisync'
sudo rm -rf '.mnlog'

# What is the actual common elements count
echo "$(./count_common.py $server_params_file -- "--------") common elements."
echo -e "As per $server_params_file\n"

mininet_exec="sudo $python_path $mininet_path                                            \
                   --latency $latency                                                    \
                   --bandwidth $bandwidth                                                \
                   --packet-loss $packet_loss                                            \
                   --cpu-server $cpu_server                                              \
                   --cpu-client $cpu_client                                              \
                   \"$benchmarks_path -p $server_params_file -m server\"                 \
                   \"$benchmarks_path -p $client_params_file -m client -r 192.168.1.1\""

echo "Mininet command:"
echo $mininet_exec

for i in `seq $repeat`
do
    echo "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
    echo "Experiment run: $i [`date`]"
    echo "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
    eval $mininet_exec
done

echo "Completed $repeat mininet_exec calls!"
