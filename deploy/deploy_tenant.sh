#!/bin/bash

AST_DIR="/opt/asterisk/etc/asterisk"
AST_BIN="/usr/sbin/asterisk"
cd $AST_DIR

add_endpoint() {
  if [ ! -f sbc_pjsip_endpoints_omls.conf ]; then
    touch sbc_pjsip_endpoints_omls.conf && chown -R asterisk. sbc_pjsip_endpoints_omls.conf
  fi
  if ! grep -q "${CUSTOMER}" sbc_pjsip_endpoints_omls.conf; then
    echo "Adding customer to sbc_pjsip_endpoints_omls.conf file"
    echo -e "\n[$CUSTOMER](omnileads_endpoints)
inbound_auth/username=$CUSTOMER
inbound_auth/password=C11H15NO2-C12h17N204P
endpoint/context=from-$CUSTOMER
endpoint/identify_by=auth_username
endpoint/set_var=TENANT=$CUSTOMER" >> sbc_pjsip_endpoints_omls.conf
    echo "Reloading pjsip"
    $AST_BIN -rx "pjsip reload"
  else
    echo "Customer configuration already exists in sbc_pjsip_endpoints_omls.conf file, nothing to do"
  fi
}

add_trunk() {
  if [ -z $TRUNK_PORT ]; then TRUNK_PORT="5060"; fi
  NOMBRE_TRUNK_PJSIP="${CUSTOMER}-${TRUNK}"
  COMMENT="${NOMBRE_TRUNK_PJSIP} ${CUSTOMER} Trunk ID="
  IS_FIRST_TRUNK=$(grep "${CUSTOMER} Trunk ID=1" sbc_pjsip_endpoints_outside.conf)
  if [ "$IS_FIRST_TRUNK" == "" ]; then
    TRUNKS_NUMBER=1
  else
    TRUNKS_NUMBER=$(expr $(grep -o "TENANT=${CUSTOMER}" sbc_pjsip_endpoints_outside.conf | wc -l) + 1)
  fi
  if [ ! -f sbc_pjsip_endpoints_outside.conf ]; then
    touch sbc_pjsip_endpoints_outside.conf && chown -R asterisk. sbc_pjsip_endpoints_outside.conf
  fi
  if ! grep -q "${NOMBRE_TRUNK_PJSIP}" sbc_pjsip_endpoints_outside.conf; then
    echo "Adding trunk to sbc_pjsip_endpoints_outside.conf file"
    echo -e "\n;For $COMMENT${TRUNKS_NUMBER}
[${NOMBRE_TRUNK_PJSIP}](outside_endpoints)
accepts_registrations=no
accepts_auth=no
sends_auth=yes
sends_registrations=yes
endpoint/set_var=TENANT=$CUSTOMER
remote_hosts=$TRUNK_IP:$TRUNK_PORT
endpoint/permit=$TRUNK_IP/32" >> sbc_pjsip_endpoints_outside.conf
    if [ ! -z $TRUNK_USER ] && [ ! -z $TRUNK_PASSWORD ]; then
      echo -e "endpoint/identify_by=ip
outbound_auth/username=$TRUNK_USER
outbound_auth/password=$TRUNK_PASSWORD">> sbc_pjsip_endpoints_outside.conf
    fi
  echo "Reloading pjsip"
  $AST_BIN -rx "pjsip reload"
  echo "Check the quantity of trunks for customer $CUSTOMER"
  echo "Number of trunks for this customer: $TRUNKS_NUMBER"
  echo "Inserting in astdb the number of trunks of customer $CUSTOMER"
  echo "Inserting in astdb the trunks name"
  $AST_BIN -rx "database put SBC/TENANT/${CUSTOMER}/TRUNK/${TRUNKS_NUMBER} NAME ""$NOMBRE_TRUNK_PJSIP"
  $AST_BIN -rx "database put SBC/TENANT/${CUSTOMER} TRUNKS ""$TRUNKS_NUMBER"
  else
    echo "This trunk already exists for this customer, nothing to do"
  fi
}

for i in "$@"
do
  case $i in
    --customer=*)
      CUSTOMER="${i#*=}"
      shift
    ;;
    --trunk=*)
      TRUNK="${i#*=}"
      shift
    ;;
    --trunk_ip=*)
      TRUNK_IP="${i#*=}"
      shift
    ;;
    --trunk_port=*)
      TRUNK_PORT="${i#*=}"
      shift
    ;;
    --trunk_user=*)
      TRUNK_USER="${i#*=}"
      shift
    ;;
    --trunk_password=*)
      TRUNK_PASSWORD="${i#*=}"
      shift
    ;;
    --help)
      echo "
        AstSBC tenant/trunk deploy script
        How to use it:
              --customer=\$CUSTOMER the name of the tenant to deploy
              --trunk=\$TRUNK the name of the trunk to add
              --trunk_ip=\$TRUNK_IP the IP/fqdn of the the trunk to add
              --trunk_port=\$TRUNK_PORT  the SIP port of the trunk to add. If not passed default port added is 5060
              --trunk_user=\$TRUNK_USER  the SIP user of the trunk to add.
              --trunk_password\$TRUNK_PASSWORD the SIP password of the trunk to add.
        "
      shift
      exit 1
    ;;
    *)
      echo "One or more invalid options, use ./deploy_tenant.sh --help"
      exit 1
    ;;
  esac
done

if [ -z ${TRUNK_IP} ] || [ -z ${CUSTOMER} ] || [ -z ${TRUNK} ]; then
  echo "The trunk IP/fqdn is mandatory, exiting"
  echo "The customer name is mandatory, exiting"
  echo "The trunk name is mandatory, exiting"
  exit 1
else
  add_endpoint
  add_trunk
fi
