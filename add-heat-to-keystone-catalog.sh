#!/bin/bash
if [[ -e "networkrc" ]]
then
    echo " * Loading local configuration from 'networkrc'..."
    source networkrc
else
  echo " * Please create networkrc file"
fi
if [[ "$UPDATE_KEYSTONE_CATALOG" == "yes" ]]
then
    echo " * Updating keystone service catalog..."

    if [[ $(keystone catalog | grep orchestration) ]]
    then
      echo "Warning: Heat already exists in the keystone service registry."
      echo "Continuing, but something may have gone wrong"
    else
      keystone service-create --name heat --type orchestration \
        --description "Orchestration"
      keystone service-create --name heat-cfn --type cloudformation \
        --description "Orchestration"
      keystone endpoint-create \
        --service-id $(keystone service-list | awk '/ orchestration / {print $2}') \
        --publicurl http://${FLOATING_IP}:8004/v1/%\(tenant_id\)s \
        --internalurl http://${FLOATING_IP}:8004/v1/%\(tenant_id\)s \
        --adminurl http://${FLOATING_IP}:8004/v1/%\(tenant_id\)s \
        --region ${REGION}
      keystone endpoint-create \
        --service-id $(keystone service-list | awk '/ cloudformation / {print $2}') \
        --publicurl http://${FLOATING_IP}:8000/v1 \
        --internalurl http://${FLOATING_IP}:8000/v1 \
        --adminurl http://${FLOATING_IP}:8000/v1 \
        --region ${REGION}
    fi
else
  echo ' * Keystone service catalog will not be updated at this point'
  echo 'You can update it later by changing networkrc file or '
  echo 'you can update manually by enterring:'
  echo "1. keystone service-create --name heat --type orchestration \\
        --description 'Orchestration'"
  echo "2. keystone service-create --name heat-cfn --type cloudformation \\
        --description 'Orchestration'"
  echo "3. keystone endpoint-create \\
        --service-id \$\(keystone service-list | awk '/ orchestration / {print $2}') \\
        --publicurl http://${FLOATING_IP}:8004/v1/%\(tenant_id\)s \\
        --internalurl http://${FLOATING_IP}:8004/v1/%\(tenant_id\)s \\
        --adminurl http://${FLOATING_IP}:8004/v1/%\(tenant_id\)s \\
        --region ${REGION}"
  echo "4. keystone endpoint-create \\
        --service-id \$\(keystone service-list | awk '/ cloudformation / {print $2}') \\
        --publicurl http://${FLOATING_IP}:8000/v1 \\
        --internalurl http://${FLOATING_IP}:8000/v1 \\
        --adminurl http://${FLOATING_IP}:8000/v1 \\
        --region ${REGION}"

fi
