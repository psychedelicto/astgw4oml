#!/bin/bash

#Parámetros para deploy_tenant.sh
CUSTOMER='felipem' # Nombre del tenant a configurar se usa tanto para outr como para deploy tenant
TRUNK='freepbx' # Nombre de la troncal PSTN a insertar
TRUNK_PORT='6066' # Puerto SIP de la troncal PSTN, si se deja vacia se toma 5060 por defecto
TRUNK_IP='201.235.179.118' # IP/fqdn de la troncal PSTN
TRUNK_USER='felo-centos' # User para autenticacion SIP con la troncal PSTN, si se deja vacia no hará autenticacion
TRUNK_PASSWORD='Password$' # Password para autenticacion SIP con la troncal PSTN, si se deja vacia no hará autenticacion

#Parametros para outr-configuration.py
TRUNKS=('freepbx') # Troncales para failover en la outr, agregar las troncales que se quieran, entre comillas simples, el orden que se ponga aca sera el orden de failover
PATTERN='_X.' # Pattern para la ruta saliente
NAME='todo' # Nombre que tendrá la ruta saliente
DIAL_TIMEOUT='' # Dial timeout para la ruta saliente, si se deja vacio toma 60 seg por defecto
PREFIX='' # Prefix para la ruta saliente. se puede dejar vacio si no se necesita prefix en la outr
PREPEND='' # Prepend para la ruta saliente. se puede dejar vacio si no se necesita prend en la outr
DIAL_OPTIONS='' # Dial options para la outr, si se deja vacio toma Tt por defecto

AMI_USER='astsbcami' # Usuario de AMI para SBC, no modificar
AMI_PASWORD='conqu33st4sami' # Password de AMI para SBC, no modificar
AST_PATH_PREFIX='/opt/asterisk'
OPTION=$1
AWS=$(which aws)

set -e

if [ "$OPTION" == "--deploy_tenant" ]; then
  comment="Run deploy_tenant.sh script for $CUSTOMER and $TRUNK"
  command="cd /root/sbc4oml/deploy && ./deploy_tenant.sh --trunk_ip=${TRUNK_IP} --customer=${CUSTOMER} --trunk=${TRUNK}"
  if [ ! -z ${TRUNK_PORT} ]; then command+=" --trunk_port=${TRUNK_PORT}"; fi
  if [ ! -z ${TRUNK_USER} ]; then command+=" --trunk_user=${TRUNK_USER}"; fi
  if [ ! -z ${TRUNK_PASSWORD} ]; then command+=" --trunk_password=${TRUNK_PASSWORD}"; fi
elif [ "$OPTION" == "--outr_configuration" ]; then
  comment="Run outr_configuration.py script for $CUSTOMER. Outr name is $NAME"
  command="cd /root/sbc4oml/deploy && AMI_USER=$AMI_USER AMI_PASSWORD=$AMI_PASWORD python3 outr_configuration.py --customer $CUSTOMER --pattern $PATTERN --name $NAME"
  for trunk in "${TRUNKS[@]}"; do
    command+=" --trunk $CUSTOMER-$trunk"
  done
  if [ ! -z ${DIAL_TIMEOUT} ]; then command+=" --dial_timeout ${DIAL_TIMEOUT}"; fi
  if [ ! -z ${PREFIX} ]; then command+=" --prefix ${PREFIX}"; fi
  if [ ! -z ${PREPEND} ]; then command+=" --prepend ${PREPEND}"; fi
  if [ ! -z ${DIAL_OPTIONS} ]; then command+=" --dial_options ${DIAL_OPTIONS}"; fi

else
  echo "Invalid option"
  exit 1
fi
echo "Command to execute in instances:"
echo "  $command"

echo "Getting instances ID's of AstSBC cluster"
INSTANCES_ID=$($AWS ec2 describe-instances \
                --filters 'Name=tag:Name,Values=*-astsbc*' 'Name=instance-state-code,Values=16'  \
                --output text \
                --query 'Reservations[].Instances[].InstanceId')
if [ -z "$INSTANCES_ID" ]; then
  echo "No hay instancias de AstSBC disponibles, saliendo"; exit 1
fi
INSTANCES_ARRAY=($INSTANCES_ID)
echo "Executing command using AWS SSM"
for instance_id in "${INSTANCES_ARRAY[@]}"
do
  sh_command_id=$($AWS ssm send-command --instance-ids "$instance_id" \
    --document-name "AWS-RunShellScript" \
    --comment "$comment" \
    --parameters commands="$command" \
    --output text \
    --query "Command.CommandId")
  sleep 5
  $AWS ssm list-command-invocations --command-id "$sh_command_id" \
    --details \
    --query "CommandInvocations[].CommandPlugins[].{Status:Status,Output:Output}"
done

echo "Getting s3 bucket name to upload configuration"
ASTSBC_BUCKET=$($AWS s3 ls |grep "astsbc" |awk -F ' ' '{print $3}')
echo "Uploading the configuration done in s3 bucket"
command="aws s3 sync $AST_PATH_PREFIX/etc/ s3://$ASTSBC_BUCKET && aws s3 cp $AST_PATH_PREFIX/var/lib/asterisk/astdb.sqlite3 s3://$ASTSBC_BUCKET/astdb.sqlite3"
echo "Command to execute for upload:"
echo "  $command"
sh_command_id=$($AWS ssm send-command --instance-ids "${INSTANCES_ARRAY[0]}" \
  --document-name "AWS-RunShellScript" \
  --comment "Upload of configuration in s3 bucket" \
  --parameters commands="$command" \
  --output text \
  --query "Command.CommandId")
sleep 5
$AWS ssm list-command-invocations --command-id "$sh_command_id" \
  --details \
  --query "CommandInvocations[].CommandPlugins[].{Status:Status,Output:Output}"
