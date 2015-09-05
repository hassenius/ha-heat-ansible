#!/bin/bash
HEAT_ADMIN_USER=$1
HEAT_ADMIN_PASSWORD=$2
if [ -z $HEAT_ADMIN_USER -o -z $HEAT_ADMIN_PASSWORD ]
then
  echo "Missing username and password input"
  exit 1
fi

echo " * Creating heat service user and roles..."
if [[ $(openstack user list | grep ${HEAT_ADMIN_USER}) ]]
then
  echo "Warning: User ${HEAT_ADMIN_USER} already exists in keystone user list"
  echo "Continuing, but something may have gone wrong"
else
  keystone user-create --name ${HEAT_ADMIN_USER} --pass ${HEAT_ADMIN_PASSWORD}
  keystone user-role-add --user ${HEAT_ADMIN_USER} --tenant service --role admin
fi

if [[ $(openstack role list | grep 'heat_stack_owner\|heat_stack_user') ]]
then
  echo "Warning: role heat_stack_owner and/or heat_stack_user already exists."
  echo "Continuing, but something may have gone wrong"
else
  keystone role-create --name heat_stack_owner
  keystone role-create --name heat_stack_user
fi
exit 0
