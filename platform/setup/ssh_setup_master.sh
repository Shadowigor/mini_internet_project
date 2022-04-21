#!/usr/bin/env bash

# Directory where the config is located
DIR="$1"

# All hosts/routers the user is allowed to connect to
readarray CONTAINERS < "${DIR}/config/allowed_containers.txt"

# Source functions to get IP addresses for the interfaces
source "${DIR}/config/subnet_config.sh"

# Create a new bridge for all connections
echo -n "-- add-br ssh_master " >> groups/add_bridges.sh

# Generate an ssh key for the container
SSH_KEY="$(mktemp)"
echo "y" | ssh-keygen -t rsa -b 4096 -C "comment" -P "" -f "$SSH_KEY" -q
docker exec -i ssh_master bash -c "mkdir -p /root/.ssh && chmod 700 /root/.ssh"
docker cp "$SSH_KEY" ssh_master:/root/.ssh/id_rsa

# Generate a password to login to the ssh container
passwd="$(openssl rand -hex 8)"
echo -e "${passwd}\n${passwd}" | docker exec -i ssh_master passwd root
echo -e "${passwd}\n${passwd}" | docker exec -i ssh_master service ssh restart

# Copy the network config files for the goto.sh script to the container
docker cp "${DIR}/config/allowed_containers.txt" ssh_master:/root/.allowed_containers.txt
docker cp "${DIR}/config/subnet_config.sh" ssh_master:/root/.subnet_config.sh

# Add a port for the ssh container
subnet="$(subnet_sshContainer_groupContainer 0 -1 -1 "sshContainer" 1)"
./setup/ovs-docker.sh add-port ssh_master ssh_master ssh_master --ipaddress="${subnet}"

# Add ports for all other containers
for CONTAINER in "${CONTAINERS[@]}"; do
    # Split up the container name
    IFS=',' read -ra SPLIT <<< "$CONTAINER"
    AS="${SPLIT[0]}"
    ROUTER="${SPLIT[1]}"
    DEVICE="${SPLIT[2]}"
    ROUTERNR="${SPLIT[3]}"

    subnet="$(subnet_sshContainer_groupContainer "$AS" "$ROUTERNR" -1 "$DEVICE" 1)"
    ./setup/ovs-docker.sh add-port ssh_master ssh_master "${AS}_${ROUTER}${DEVICE}" --ipaddress="${subnet}"
    docker cp "${SSH_KEY}.pub" "${AS}_${ROUTER}${DEVICE}":/root/.ssh/authorized_keys2
done
