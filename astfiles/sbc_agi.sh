#!/bin/bash

D=/var/log/asterisk/

declare -a array 
while read -e ARG && [ "$ARG" ] ; do 
        array=(` echo $ARG | sed -e 's/://'`) 
        export ${array[0]}=${array[1]} 
done 

# following variables are available from asterisk 
echo $agi_request >&2 
echo $agi_channel >&2 
echo $agi_language >&2 
echo $agi_type >&2 
echo $agi_uniqueid >&2 
echo $agi_callerid >&2 
echo $agi_dnid >&2 
echo $agi_rdnis >&2 
echo $agi_context >&2 
echo $agi_extension >&2 
echo $agi_priority >&2 
echo $agi_enhanced >&2 

#uniqueid=[$1] tenant_name=[$2] type=[$3] trunk=[$4] result=[$5] src=[$6] dst=[$7] duration=[$8] rate=[$9] campaign=[$10] recording=[$11]" >> $D/scb.log

echo -e "`date +%Y-%m-%d`,`date +%H:%M:%S`,$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11" >> $D/sbc.log

