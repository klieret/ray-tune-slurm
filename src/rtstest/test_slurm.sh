#!/bin/bash
# shellcheck disable=SC2206

# THIS FILE WAS FIRST CREATED WITH THE CONFIG CREATOR FROM THE RAY TUNE TUTORIAL
# However, some flags that weren't understood by tigergpu were removed again.

#SBATCH --job-name=first_slurm_job.sh
#SBATCH --output=first_slurm_job.sh.log

### This script works for any number of nodes, Ray will find and manage all resources
#SBATCH --nodes=10
#SBATCH --exclusive
### Give all resources to a single Ray task, ray can manage the resources internally
#SBATCH --ntasks-per-node=1
#SBATCH --gres=gpu:4             # number of gpus per node
#SBATCH --time=00:01:30          # total run time limit (HH:MM:SS)
# Load modules or your own conda environment here
# module load pytorch/v1.4.0-gpu
# conda activate ${CONDA_ENV}

# ===== DO NOT CHANGE THINGS HERE UNLESS YOU KNOW WHAT YOU ARE DOING =====
# This script is a modification to the implementation suggest by gregSchwartz18 here:
# https://github.com/ray-project/ray/issues/826#issuecomment-522116599
redis_password=$(uuidgen)
export redis_password

nodes=$(scontrol show hostnames "$SLURM_JOB_NODELIST") # Getting the node names
nodes_array=($nodes)

node_1=${nodes_array[0]}
ip=$(srun --nodes=1 --ntasks=1 -w "$node_1" hostname --ip-address) # making redis-address

# if we detect a space character in the head node IP, we'll
# convert it to an ipv4 address. This step is optional.
if [[ "$ip" == *" "* ]]; then
  IFS=' ' read -ra ADDR <<< "$ip"
  if [[ ${#ADDR[0]} -gt 16 ]]; then
    ip=${ADDR[1]}
  else
    ip=${ADDR[0]}
  fi
  echo "IPV6 address detected. We split the IPV4 address as $ip"
fi

port=6379
ip_head=$ip:$port
export ip_head
echo "IP Head: $ip_head"

echo "STARTING HEAD at $node_1"
srun --nodes=1 --ntasks=1 -w "$node_1" \
  ray start --head --node-ip-address="$ip" --port=$port --redis-password="$redis_password" --block &
sleep 30

worker_num=$((SLURM_JOB_NUM_NODES - 1)) #number of nodes other than the head node
for ((i = 1; i <= worker_num; i++)); do
  node_i=${nodes_array[$i]}
  echo "STARTING WORKER $i at $node_i"
  srun --nodes=1 --ntasks=1 -w "$node_i" ray start --address "$ip_head" --redis-password="$redis_password" --block &
  sleep 5
done

# ===== Call your code below =====
python3 dothetune.py
