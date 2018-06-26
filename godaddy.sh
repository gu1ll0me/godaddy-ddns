#!/bin/bash

# GoDaddy.sh v1.0 by Nazar78 @ TeaNazaR.com
###########################################
# Simple DDNS script to update GoDaddy's DNS. Just schedule every 5mins in crontab.
# With options to run scripts/programs/commands on update failure/success.
#
# Requirements:
# - Bash - On LEDE/OpenWRT, opkg install bash
# - curl CLI - On Debian, apt-get install curl
#
# History:
# v1.0 - 20160513 - 1st release.
#
# PS: Feel free to distribute but kindly retain the credits (-:
###########################################

# Begin settings
# Get the Production API key/secret from https://developer.godaddy.com/keys/.
# Ensure it's for "Production" as first time it's created for "Test".
Key=<API production key>
Secret=<API secret>

# Domain to update.
Domain=<domain name>

# Advanced settings - change only if you know what you're doing :-)
# Record type, as seen in the DNS setup page, default A.
Type=A

# Record name, as seen in the DNS setup page, default @.
Name=@

# Time To Live in seconds, minimum default 600 (10mins).
# If your public IP seldom changes, set it to 3600 (1hr) or more for DNS servers cache performance.
TTL=600

# Writable path to last known Public IP record cached. Best to place in tmpfs.
CachedIP=/tmp/current_ip

# External URL to check for current Public IP, must contain only a single plain text IP.
# Default http://api.ipify.org.
CheckURL=http://api.ipify.org

# Optional scripts/programs/commands to execute on successful update. Leave blank to disable.
# This variable will be evaluated at runtime but will not be parsed for errors nor execution guaranteed.
# Take note of the single quotes. If it's a script, ensure it's executable i.e. chmod 755 ./script.
# Example: SuccessExec='/bin/echo "$(date): My public IP changed to ${PublicIP}!">>/var/log/GoDaddy.sh.log'
SuccessExec=''

# Optional scripts/programs/commands to execute on update failure. Leave blank to disable.
# This variable will be evaluated at runtime but will not be parsed for errors nor execution guaranteed.
# Take note of the single quotes. If it's a script, ensure it's executable i.e. chmod 755 ./script.
# Example: FailedExec='/some/path/something-went-wrong.sh ${Update} && /some/path/email-script.sh ${PublicIP}'
FailedExec=''
# End settings

Curl=$(/usr/bin/which curl 2>/dev/null)
Touch=$(/usr/bin/which touch 2>/dev/null)
[ "${Curl}" = "" ] &&
echo "Error: Unable to find 'curl CLI'." && exit 1
[ -z "${Key}" ] || [ -z "${Secret}" ] &&
echo "Error: Requires API 'Key/Secret' value." && exit 1
[ -z "${Domain}" ] &&
echo "Error: Requires 'Domain' value." && exit 1
[ -z "${Type}" ] && Type=A
[ -z "${Name}" ] && Name=@
[ -z "${TTL}" ] && TTL=600
[ "${TTL}" -lt 600 ] && TTL=600
${Touch} ${CachedIP} 2>/dev/null
[ $? -ne 0 ] && echo "Error: Can't write to ${CachedIP}." && exit 1
[ -z "${CheckURL}" ] && CheckURL=http://api.ipify.org
echo -n "Checking current 'Public IP' from '${CheckURL}'..."
PublicIP=$(${Curl} -kLs ${CheckURL})
if [ $? -eq 0 ] && [[ "${PublicIP}" =~ [0-9]{1,3}\.[0-9]{1,3} ]];then
  echo "${PublicIP}!"
else
  echo "Fail! ${PublicIP}"
  eval ${FailedExec}
  exit 1
fi
if [ "$(cat ${CachedIP} 2>/dev/null)" != "${PublicIP}" ];then
  echo -n "Checking '${Domain}' IP records from 'GoDaddy'..."
  Check=$(${Curl} -kLsH"Authorization: sso-key ${Key}:${Secret}" \
  -H"Content-type: application/json" \
  https://api.godaddy.com/v1/domains/${Domain}/records/${Type}/${Name} \
  2>/dev/null|jq -r '.[0].data')
  if [ $? -eq 0 ] && [ "${Check}" = "${PublicIP}" ];then
    echo -n ${Check}>${CachedIP}
    echo -e "unchanged!\nCurrent 'Public IP' matches 'GoDaddy' records. No update required!"
  else
    echo -en "changed!\nUpdating '${Domain}' ${Check} -> ${PublicIP}..."
    Update=$(${Curl} -kLsXPUT -H"Authorization: sso-key ${Key}:${Secret}" \
    -H"Content-type: application/json" \
    https://api.godaddy.com/v1/domains/${Domain}/records/${Type}/${Name} \
    -d "[{\"data\":\"${PublicIP}\",\"ttl\":${TTL}}]" 2>/dev/null)
    if [ $? -eq 0 ] && [ "${Update}" = "" ];then
      echo -n ${PublicIP}>${CachedIP}
      echo "Success!"
      eval ${SuccessExec}
    else
      echo "Fail! ${Update}"
      eval ${FailedExec}
      exit 1
    fi
  fi
else
  echo "Current 'Public IP' matches 'Cached IP' recorded. No update required!"
fi
exit $?
