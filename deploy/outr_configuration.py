# -*- coding: utf-8 -*-

import argparse
import re
import sys, os, stat
from asterisk.manager import Manager, ManagerSocketException, ManagerAuthException, ManagerException

parser = argparse.ArgumentParser(description='SBC Outr configuration script', add_help=True)

parser.add_argument("--customer", help="The tenant that will own the outr")
parser.add_argument("--pattern", help="The pattern for this outr")
#parser.add_argument("--help", help="Sets internal IP in external server, say 172.16.20.44")
parser.add_argument("--name", help="The name that will have this outr")
parser.add_argument("--dial_options", help="The dial options for this route, this option is not mandatory")
parser.add_argument("--dial_timeout", help="The dial timeout for this route, this option is not mandatory")
parser.add_argument("--prefix", help="Prefix for this route, this option is not mandatory")
parser.add_argument("--prepend", help="Prepend for this route, this option is not mandatory")
parser.add_argument("--trunk", action="append", help="Specifies the trunk or trunks for this route. You can insert more than one trunk, the order you insert the trunks will be the order of failover")
args = vars(parser.parse_args())

outr_file = "/opt/asterisk/etc/asterisk/sbc_extensions_to_outside.conf"
trunks_file = "/opt/asterisk/etc/asterisk/sbc_pjsip_endpoints_outside.conf"

if not os.path.exists(outr_file):
    os.mknod(outr_file)
    os.chown(outr_file, 999, 999)
    os.chmod(outr_file, 0o755)

customer = args['customer']
pattern = args['pattern']
name = args['name']
args_passed = ['NAME']
trunks_name = []
if args['dial_options']:
    dial_options = args['dial_options']
    args_passed.append('DIALOPTIONS')
if args['dial_timeout']:
    dial_timeout = args['dial_timeout']
    args_passed.append('DIALTIME')
if args['prefix']:
    prefix = args['prefix']
    args_passed.append('PREFIX')
if args['prepend']:
    prepend = args['prepend']
    args_passed.append('PREPEND')
args_passed.append('TRUNKS')
for trunk in args['trunk']:
    trunks_name.append(trunk)
    args_passed.append('TRUNK')


def write_extensions_to_outside_file():
    if customer and pattern:
        to_escape = ['${CONTEXT}', '${TENANT}', '${EXTEN}']
        strings_escaped = []
        for i in to_escape:
            escaped = i.translate(str.maketrans({"$":  r"\$"}))
            strings_escaped.append(re.escape(i).replace("\\", ""))
        data = open(outr_file).read()
        times_found = data.count(customer)
        if times_found == 0:
            outr_id = 1
        else:
            outr_id = times_found
        if customer not in data:
            content = ("\n[from-{0}]\n").format(customer)
        else:
            content = ("")
        mensaje = ';ruta ' + pattern + ' para ' + customer
        for line in data.split("\n"):
            if mensaje in line:
                outr_id = int(line.split("=")[1])
        if mensaje not in data:
            print("Writting the outr for this customer in sbc_extensions_to_outside.conf file")
            content += (';ruta {1} para {0} con ID={2}\n'
                        'exten => {1},1,Verbose(Ruta {2} para tenant {3})\n'
                        "same => n,Gosub(sbc-to-outside,s,1({4},{2},{5}))\n"
                        "same => n,Hangup()\n\n").format(customer, pattern, outr_id, strings_escaped[0], strings_escaped[1], strings_escaped[2])
            with open(outr_file, "a") as myfile:
                myfile.write(content)
                myfile.close()
        else:
            print("**WARNING**:The pattern ingressed was already set for this customer in sbc_extensions_to_outside.conf file")
    else:
        print("**ERROR:**  --customer and --pattern options are mandatory")
    return outr_id


def check_if_trunk_exists(trunk_order):
    data = open(trunks_file).read()
    trunk_id = ""
    for line in data.split("\n"):
        if 'For ' + trunks_name[trunk_order-1] + ' ' + customer in line:
            trunk_id = str(line.split("=")[1])
    if trunk_id == "":
        print("**ERROR:** One or more trunks you are trying to use doesn't exist, please first add the trunks")
        sys.exit()
    return trunk_id


def check_if_customer_exists():
    data = open(trunks_file).read()
    if not 'set_var=TENANT=' + customer in data:
        print("**ERROR:** The customer you are trying to use doesn't exist, please first add the customer")
        sys.exit()


def set_asteriskdb(outr_id):
    if name and trunks_name:
        manager = Manager()
        ami_manager_user = os.getenv('AMI_USER')
        ami_manager_pass = os.getenv('AMI_PASSWORD')
        ami_manager_host = '127.0.0.1'
        trunk_order = 1
    #    keys = ['NAME', 'DIALOPTIONS', 'DIALTIME', 'PREFIX', 'PREPEND', 'TRUNKS']
        family = 'SBC/TENANT/' + customer + '/OUTR/' + str(outr_id)
        try:
            print("Conectting to the manager")
            manager.connect(ami_manager_host)
            print("Logging to the manager with provided credentials")
            manager.login(ami_manager_user, ami_manager_pass)
            print("Reloading asterisk dialplan")
            manager.command("dialplan reload")
            print("Erasing previous entries of TRUNKS OUTR family")
            manager.command("database deltree SBC/TENANT/" + customer + "/OUTR/" + str(outr_id) + "/TRUNK")
            for key in args_passed:
                if key == "DIALOPTIONS":
                    value = dial_options
                elif key == "DIALTIME":
                    value = dial_timeout
                elif key == "NAME":
                    value = name
                elif key == "PREFIX":
                    value = prefix
                elif key == "PREPEND":
                    value = prepend
                elif key == "TRUNKS":
                    value = len(args['trunk'])
                if key == "TRUNK":
                    family = 'SBC/TENANT/' + customer + '/OUTR/' + str(outr_id) + '/TRUNK'
                    if trunk_order <= len(args['trunk']):
                        key = str(trunk_order)
                        value = check_if_trunk_exists(trunk_order)
                        trunk_order = trunk_order + 1
                print("Inserting " + family + " " + key + " " + str(value) + " in astdb")
                data_returned = manager.dbput(family, key, value)
            if not args['prefix'] or not args['prepend']:
                if not args['prefix']:
                    key = 'PREFIX'
                elif not args['prepend']:
                    key = 'PREPEND'
                family = 'SBC/TENANT/' + customer + '/OUTR/' + str(outr_id)
                data_returned = manager.dbget(family, key)
                if str(data_returned) == 'Success':
                    manager.dbdel(family, key)
            manager.close()
        except ManagerSocketException as e:
            print("**ERROR:**  Error connecting to the manager: {0}".format(e))
        except ManagerAuthException as e:
            print("**ERROR:**  Error logging in to the manager: {0}".format(e))
        except ManagerException as e:
            print("**ERROR:**  Error {0}".format(e))
        return data_returned
    else:
        print("**ERROR:** --trunk and --name options are mandatory")


check_if_customer_exists()
set_asteriskdb(write_extensions_to_outside_file())
