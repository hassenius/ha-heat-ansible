#!/bin/bash
## Notes:
## If one of the VMs fail preferred procedure would be:
# Approach 1. 
#  rebuild the VM and rerun ansible scripts. This maintains the IP of the instance
#  If that does not work:
# Approach 2. 
#  if the VM needs to be deleted from nova, then manually use neutron port-create to attempt to get 
#  the same ip as the failed instance had
#  then rerun setup.sh to recreate the failed instance, then rerun ansible script
#  If that does not work:
# Approach 3.
#  Things will need to be rebuilt and recalibrated manually
set -e 

if [[ -e "networkrc" ]]
then
    echo " * Loading local configuration from 'networkrc'..."
    source networkrc
else
  echo " * Please create networkrc file"
fi

if [[ "${CREATE_PORTS}" == "yes" ]]
then
  # Create the neutron ports
  for name in heat_backend1 heat_backend2 heat_frontend1 heat_frontend2 
  do
    echo " * Creating neutron port ${name}: "
    neutron port-create ${NETWORK} --name ${name} -c fixed_ips -f value
  done
  
  echo "Creating Floating IP: "
  VIP_PORT=$(neutron port-show heat_frontendvip -c id -f value)
  FLOATING_IP=$(neutron floatingip-create $FLOATING_NET --port-id $VIP_PORT -c floating_ip_address -f value)
  echo "Associated IP: ${FLOATING_IP}"
  # Update the config
  sed -i.port-bak 's/CREATE_PORTS=yes/CREATE_PORTS=no/g' networkrc
  echo "FLOATING_IP=${FLOATING_IP}" >> networkrc
fi

# If frontend VIP is not set, assume neutron port setup needs to be done
if [[ -z "${FRONTEND_VIP}" ]]
then
  echo -n " * Finding front end VIP address: "
  FRONTEND_VIP=$(neutron port-show heat_frontendvip | awk -F ":" '/ip_address/ { print $3 }' | tr -dc '0-9.')
  echo " Found ${FRONTEND_VIP}"
  echo "FRONTEND_VIP=${FRONTEND_VIP}" >> networkrc

  # Set allowed address pairs for frontend ports to allow them use the VIP
  for name in heat_frontend1 heat_frontend2
  do
    port_ip=$(neutron port-show ${name} | awk -F ":" '/ip_address/ { print $3 }' | tr -dc '0-9.')
    echo " * Updating Neutron port ${name} to allow own ip ${port_ip} and vip ${FRONTEND_VIP}"
    neutron port-update ${name} --allowed_address_pairs list=true type=dict ip_address=${port_ip} ip_address=${FRONTEND_VIP}
    echo "${name}=${port_ip}" >> networkrc
  done
  
  # Add the back-end servers
  for name in heat_backend1 heat_backend2
  do
    port_ip=$(neutron port-show ${name} | awk -F ":" '/ip_address/ { print $3 }' | tr -dc '0-9.')
    echo "${name}=${port_ip}" >> networkrc
  done
  
  
  # Refresh the network settings to get the ip addresses
  source networkrc
fi


## Create servers
for server in heat_backend1 heat_backend2 heat_frontend1 heat_frontend2
do
  set +e
  echo " * Checking if ${server} already exists"
  serverstatus=$(openstack server show $server -c status -f value 2>/dev/null)
  RETVAL=$?
  set -e
  if [ "$RETVAL" == "0" ]
  then
    if [ "${serverstatus}" == "ACTIVE" ]
    then
      echo " * Server ${server} already exists and is active"
      echo "Continuing to next server...."
      continue
    else
      echo " * Server ${server} already exists, but state is ${serverstatus}"
      echo "ERROR: You will need to manually correct this and rerun script"
      exit 1
    fi
  fi
  
  if [ "${server}" == "heat_backend2" ]
  then
    # We need to set scheduler hints to get different hypervisor from heat_backend1
    echo "Anti-colocation with heat_backend1 to be implemented..."
    scheduler_hint=""
  fi
  
  if [ "${server}" == "heat_frontend2" ]
  then
    # We need to set scheduler hints to get different hypervisor from heat_backend1
    echo "Anti-colocation with heat_frontend1 to be implemented"
    scheduler_hint=""
  fi
  
  # Create the servers
  portid=$(neutron port-show ${server} -c id -f value)
  echo -n " * Building server ${server}: "
  openstack --quiet server create ${server} --flavor ${NOVA_FLAVOR} --image "${NOVA_IMAGE}" --nic port-id=$portid --key-name ${NOVA_KEYNAME} ${scheduler_hint} -c status -f value
  unset $scheduler_hint

done

echo " * Creating heat service user and roles..."
if [[ $(openstack --quiet user list | grep ${HEAT_ADMIN_USER}) ]]
then
  echo "Warning: User ${HEAT_ADMIN_USER} already exists in keystone user list"
  echo "Continuing, but something may have gone wrong"
else
  echo "Adding user ${HEAT_ADMIN_USER}"
  keystone user-create --name ${HEAT_ADMIN_USER} --pass ${HEAT_ADMIN_PASSWORD}
  keystone user-role-add --user ${HEAT_ADMIN_USER} --tenant service --role admin
fi

if [[ $(openstack --quiet role list | grep 'heat_stack_owner\|heat_stack_user') ]]
then
  echo "Warning: role heat_stack_owner and/or heat_stack_user already exists."
  echo "Continuing, but something may have gone wrong"
else
echo "Adding heat roles"
  keystone role-create --name heat_stack_owner
  keystone role-create --name heat_stack_user
fi

if [ "$1" == "update-ips" ]
then
  echo "updating the ip configuration files"
  for name in heat_backend1 heat_backend2 heat_frontend1 heat_frontend2
  do
    port_ip=$(neutron port-show ${name} | awk -F ":" '/ip_address/ { print $3 }' | tr -dc '0-9.')
    sed -i "s/^${name}=[0-9\.]*/${name}=${port_ip}/g" networkrc
    echo "${name}=${port_ip}" >> networkrc
  done
  source networkrc
fi

# Update ansible hosts file
sed -i "s/heat_frontend_vip=[0-9\.]*/heat_frontend_vip=${FRONTEND_VIP}/g" hosts
sed -i "s/backend1=[0-9\.]*/backend1=${heat_backend1}/g" hosts
sed -i "s/backend2=[0-9\.]*/backend2=${heat_backend2}/g" hosts
sed -i "s/heat_endpoint_ip=[0-9\.]*/heat_endpoint_ip=${FLOATING_IP}/g" hosts

echo "Please verify ./hosts"
# Update hosts file
echo "You'll need to manually verify that /etc/hosts includes the following entries: "
for host in heat_backend1 heat_backend2 heat_frontend1 heat_frontend2 
do
  echo "${!host} ${host}"
done

echo "After verifying, please run:"
echo "ansible-playbook -i ./hosts site.yaml"


