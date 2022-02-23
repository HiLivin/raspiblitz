#!/bin/bash

# This is a template bonus script you can use to add your app to RaspiBlitz.
# So just copy it within the `/home.admin/config.scripts` directory and
# rename it for your app - example: `bonus.myapp.sh`.
# Then go thru this script and delete parts/comments you dont need or add
# needed configurations.

# id string of your app (short single string unique in raspiblitz)
# should be same as used in name if script
APPID="TEMPLATE" # one-word lower-case no-specials  

# the git repo to get the source code from for install
GITHUB_REPO="https://github.com/rootzoll/raspiblitz-template"

# the github tag of the version of the source code to install
# can also be a commit hash 
# if empty it will use the latest source version
GITHUB_VERSION="v0.1"

# the github signature to verify the author
# if empty verifying the git author will be 
GITHUB_SIGNATURE=""

# port numbers the app should run on
# delete if not an web app
PORT_NATIVE="12345"
PORT_SSL="12346"

# BASIC COMMANDLINE OPTIONS
# you can add more actions or parameters if needed - for example see the bonus.rtl.sh
# to see how you can deal with an app that installs multiple instances depending on
# lightning implementation or testnets - but this should be OK for a start:
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# bonus.${APPID}.sh status   -> status information (key=value)"
  echo "# bonus.${APPID}.sh on       -> install the app"
  echo "# bonus.${APPID}.sh off      -> uninstall the app"
  echo "# bonus.${APPID}.sh menu     -> SSH menu dialog"
  echo "# bonus.${APPID}.sh prestart -> will be called by systemd before start"
  exit 1
fi

# echoing comments is useful for logs - but start output with # when not a key=value 
echo "# Running: 'bonus.${APPID}.sh $*'"

# check & load raspiblitz config
source /mnt/hdd/raspiblitz.conf

##########################
# INFO
#########################

# this section is always executed to gather status information that
# all the following commands can use & execute on

# check if app is already installed
isInstalled=$(sudo ls /etc/systemd/system/${APPID}.service 2>/dev/null | grep -c "${APPID}.service")

# check if service is running
isRunning=$(systemctl status ${APPID} 2>/dev/null | grep -c 'active (running)')

if [ "${isInstalled}" == "1" ]; then

  # gather address info (whats needed to call the app)
  localIP=$(hostname -I | awk '{print $1}')
  toraddress=$(sudo cat /mnt/hdd/tor/${APPID}/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

fi

# if the action parameter `info` was called - just stop here and output all
# status information as a key=value list
if [ "$1" = "menu" ]; then
  echo "appID='${APPID}'"
  echo "githubRepo='${GITHUB_REPO}'"
  echo "githubVersion='${GITHUB_VERSION}'"
  echo "githubSignature='${GITHUB_SIGNATURE}'"  
  echo "isInstalled=${isInstalled}"
  echo "isRunning=${isRunning}"
  if [ "${isInstalled}" == "1" ]; then
    echo "portBASIC=${PORT_NATIVE}"
    echo "portSSL=${PORT_SSL}"
    echo "localIP='${localIP}'"
    echo "toraddress='${toraddress}'"
    echo "fingerprint='${fingerprint}'"
  fi
  exit
fi

##########################
# MENU
#########################

# The `menu` action should give at least a SSH info dialog - when an webapp show
# URL to call (http & https+fingerprint) otherwise some instruction how to start it.

# This SSH dialog can be added to MAIN MENU to be available to the user
# when app is istalled (see/edit 00mainmenu.sh script).

# This menu can also have some more complex structure if you want to make it easy
# to the user to set configurations or maintance options - example bonus.lnbits.sh

# show info menu
if [ "$1" = "menu" ]; then


  # TODO construct menu based if tor address is available ....


  # info with Tor
  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    sudo /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    whiptail --title "Ride The Lightning (RTL - $LNTYPE - $CHAIN)" --msgbox "Open in your local web browser:
http://${localip}:${RTLHTTP}\n
https://${localip}:$((RTLHTTP+1)) with Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
Hidden Service address for Tor Browser (QRcode on LCD):\n${toraddress}
" 16 67
    sudo /home/admin/config.scripts/blitz.display.sh hide

  # info without Tor
  else
    whiptail --title "Ride The Lightning (RTL - $LNTYPE - $CHAIN)" --msgbox "Open in your local web browser & accept self-signed cert:
http://${localip}:${RTLHTTP}\n
https://${localip}:$((RTLHTTP+1)) with Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
Activate Tor to access the web interface from outside your local network.
" 15 67
  fi
  echo "please wait ..."
  exit 0
fi

##########################
# ON
#########################

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # check that parameters are set
  if [ "${LNTYPE}" == "" ] || [ "${CHAIN}" == "" ]; then
    echo "# missing parameter"
    exit 1
  fi

  # check that is installed
  isInstalled=$(sudo ls /etc/systemd/system/${systemdService}.service 2>/dev/null | grep -c "${systemdService}.service")
  if [ ${isInstalled} -eq 1 ]; then
    echo "# OK, the ${netprefix}${typeprefix}RTL.service is already installed."
    exit 1
  fi

  echo "# Installing RTL for ${LNTYPE} ${CHAIN}"

  # check and install NodeJS
  /home/admin/config.scripts/bonus.nodejs.sh on

  # create rtl user (one for all instances)
  if [ $(compgen -u | grep -c rtl) -eq 0 ];then
    sudo adduser --disabled-password --gecos "" rtl || exit 1
  fi
  echo "# Make sure symlink to central app-data directory exists"
  if ! [[ -L "/home/rtl/.lnd" ]]; then
    sudo rm -rf "/home/rtl/.lnd" 2>/dev/null              # not a symlink.. delete it silently
    sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/rtl/.lnd"  # and create symlink
  fi
  if [ "${LNTYPE}" == "lnd" ]; then
    # for LND make sure user rtl is allowed to access admin macaroons
    echo "# adding user rtl to group lndadmin"
    sudo /usr/sbin/usermod --append --groups lndadmin rtl
  fi

  # source code (one place for all instances)
  if [ -f /home/rtl/RTL/LICENSE ];then
    echo "# OK - the RTL code is already present"
    cd /home/rtl/RTL
  else
    # download source code and set to tag release
    echo "# Get the RTL Source Code"
    sudo -u rtl rm -rf /home/rtl/RTL 2>/dev/null
    sudo -u rtl git clone https://github.com/ShahanaFarooqui/RTL.git /home/rtl/RTL
    cd /home/rtl/RTL
    # check https://github.com/Ride-The-Lightning/RTL/releases/
    sudo -u rtl git reset --hard $RTLVERSION
    PGPsigner="saubyk"
    PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
    PGPpubkeyFingerprint="00C9E2BC2E45666F"
    sudo -u rtl /home/admin/config.scripts/blitz.git-verify.sh \
     "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" "${RTLVERSION}" || exit 1
    # from https://github.com/Ride-The-Lightning/RTL/commits/master
    # git checkout 917feebfa4fb583360c140e817c266649307ef72
    if [ -f /home/rtl/RTL/LICENSE ]; then
      echo "# OK - RTL code copy looks good"
    else
      echo "# FAIL - RTL code not available"
      echo "err='code download falied'"
      exit 1
    fi
    # install
    echo "# Run: npm install"
    export NG_CLI_ANALYTICS=false
    sudo -u rtl npm install --only=prod --logLevel warn
    if ! [ $? -eq 0 ]; then
      echo "# FAIL - npm install did not run correctly - deleting code and exit"
      sudo rm -r /home/rtl/RTL
      exit 1
    else
      echo "# OK - RTL install looks good"
      echo
    fi
  fi

  echo "# Updating Firewall"
  sudo ufw allow ${RTLHTTP} comment "${systemdService} HTTP"
  sudo ufw allow $((RTLHTTP+1)) comment "${systemdService} HTTPS"
  echo

  # make sure config directory exists
  sudo mkdir -p /mnt/hdd/app-data/rtl 2>/dev/null
  sudo chown -R rtl:rtl /mnt/hdd/app-data/rtl

  echo "# Create Systemd Service: ${systemdService}.service (Template)"
  echo "
# Systemd unit for ${systemdService}

[Unit]
Description=${systemdService} Webinterface
Wants=
After=

[Service]
Environment=\"RTL_CONFIG_PATH=/mnt/hdd/app-data/rtl/${systemdService}/\"
ExecStartPre=-/home/admin/config.scripts/bonus.rtl.sh prestart ${LNTYPE} ${CHAIN}
ExecStart=/usr/bin/node /home/rtl/RTL/rtl
User=rtl
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${systemdService}.service
  sudo chown root:root /etc/systemd/system/${systemdService}.service

  # adapt systemd service template for LND
  if [ "${LNTYPE}" == "lnd" ]; then
    echo "# modifying ${systemdService}.service for LND"
    sudo sed -i "s/^Wants=.*/Wants=${netprefix}lnd.service/g" /etc/systemd/system/${systemdService}.service
    sudo sed -i "s/^After=.*/After=${netprefix}lnd.service/g" /etc/systemd/system/${systemdService}.service
  fi
  # adapt systemd service template for
  if [ "${LNTYPE}" == "cl" ]; then
    echo "# modifying ${systemdService}.service for CL"
    sudo sed -i "s/^Wants=.*/Wants=${netprefix}lightningd.service/g" /etc/systemd/system/${systemdService}.service
    sudo sed -i "s/^After=.*/After=${netprefix}lightningd.service/g" /etc/systemd/system/${systemdService}.service

    # set up C-LightningREST
    /home/admin/config.scripts/cl.rest.sh on ${CHAIN}
  fi

  # Note about RTL config file
  echo "# NOTE: the RTL config for this instance will be done on the fly as a prestart in systemd"

  # Hidden Service for RTL if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with tor.network.sh script
    /home/admin/config.scripts/tor.onion-service.sh ${netprefix}${typeprefix}RTL 80 $((RTLHTTP+2)) 443 $((RTLHTTP+3))
  fi

  # nginx configuration
  echo "# Setup nginx confs"
  sudo cp /home/admin/assets/nginx/sites-available/rtl_ssl.conf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_ssl.conf
  sudo cp /home/admin/assets/nginx/sites-available/rtl_tor.conf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor.conf
  sudo cp /home/admin/assets/nginx/sites-available/rtl_tor_ssl.conf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor_ssl.conf
  sudo sed -i "s/3000/$RTLHTTP/g" /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_ssl.conf
  sudo sed -i "s/3001/$((RTLHTTP+1))/g" /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_ssl.conf
  sudo sed -i "s/3000/$RTLHTTP/g" /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor.conf
  sudo sed -i "s/3002/$((RTLHTTP+2))/g" /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor.conf
  sudo sed -i "s/3000/$RTLHTTP/g" /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor_ssl.conf
  sudo sed -i "s/3003/$((RTLHTTP+3))/g" /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor_ssl.conf
  sudo ln -sf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_ssl.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor_ssl.conf /etc/nginx/sites-enabled/
  sudo nginx -t
  sudo systemctl reload nginx

  # run config as root to connect prepare services (lit, pool, ...)
  sudo /home/admin/config.scripts/bonus.rtl.sh connect-services

  # ig
  /home/admin/config.scripts/blitz.conf.sh set ${configEntry} "on"

  sudo systemctl enable ${systemdService}
  sudo systemctl start ${systemdService}
  echo "# OK - the ${systemdService}.service is now enabled & started"
  echo "# Monitor with: sudo journalctl -f -u ${systemdService}"
  exit 0
fi

##########################
# CONNECT SERVICES
# will be called by lit or loop services to make sure services
# are connected or on RTL install/update
#########################

if [ "$1" = "connect-services" ]; then

  # has to run as use root or sudo
  if [ "$USER" != "root" ] && [ "$USER" != "admin" ]; then
    echo "# FAIL: run as user root or admin"
    exit 1
  fi

  # only run when RTL is installed
  if [ -d /home/rtl ]; then
    echo "## RTL CONNECT-SERVICES"
  else
    echo "# no RTL installed - no need to connect any services"
    exit
  fi

  # LIT & LOOP Swap Server
  echo "# checking of swap server ..."
  if [ "${lit}" = "on" ]; then
    echo "# LIT DETECTED"
    echo "# Add the rtl user to the lit group"
    sudo /usr/sbin/usermod --append --groups lit rtl
    echo "# Symlink the lit-loop.macaroon"
    sudo rm -rf "/home/rtl/.loop"                    #  delete symlink
    sudo ln -s "/home/lit/.loop/" "/home/rtl/.loop"  # create symlink
    echo "# Make the loop macaroon group readable"
    sudo chmod 640 /home/rtl/.loop/mainnet/macaroons.db
  elif [ "${loop}" = "on" ]; then
    echo "# LOOP DETECTED"
    echo "# Add the rtl user to the loop group"
    sudo /usr/sbin/usermod --append --groups loop rtl
    echo "# Symlink the loop.macaroon"
    sudo rm -rf "/home/rtl/.loop"                     # delete symlink
    sudo ln -s "/home/loop/.loop/" "/home/rtl/.loop"  # create symlink
    echo "# Make the loop macaroon group readable"
    sudo chmod 640 /home/rtl/.loop/mainnet/macaroons.db
  else
    echo "# No lit or loop single detected"
  fi

  echo "# RTL CONNECT-SERVICES done"
  exit 0

fi

##########################
# PRESTART
# - will be called as prestart by systemd service (as user rtl)
#########################

if [ "$1" = "prestart" ]; then

  # check that parameters are set
  if [ "${LNTYPE}" == "" ] || [ "${CHAIN}" == "" ]; then
    echo "# missing parameter"
    exit 1
  fi

  # users need to be `rtl` so that it can be run by systemd as prestart (no SUDO available)
  if [ "$USER" != "rtl" ]; then
    echo "# FAIL: run as user rtl"
    exit 1
  fi

  echo "## RTL PRESTART CONFIG (called by systemd prestart)"

  # getting the up-to-date RPC password
  RPCPASSWORD=$(cat /mnt/hdd/${network}/${network}.conf | grep "^rpcpassword=" | cut -d "=" -f2)
  echo "# Using RPCPASSWORD(${RPCPASSWORD})"

  # determine correct loop swap server port (lit over loop single)
  if [ "${lit}" = "on" ]; then
      echo "# use lit loop port"
      SWAPSERVERPORT=8443
  elif [ "${loop}" = "on" ]; then
      echo "# use loop single instance port"
      SWAPSERVERPORT=8081
  else
      echo "# No lit or loop single detected"
      SWAPSERVERPORT=""
  fi

  # prepare RTL-Config.json file
  echo "# PREPARE /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json"

  # make sure directory exists
  mkdir -p /mnt/hdd/app-data/rtl/${systemdService} 2>/dev/null

  # check if RTL-Config.json exists
  configExists=$(ls /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json 2>/dev/null | grep -c "RTL-Config.json")
  if [ "${configExists}" == "0" ]; then
    # copy template
    cp /home/rtl/RTL/Sample-RTL-Config.json /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json
    chmod 600 /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json
  fi

  # LND changes of config
  if [ "${LNTYPE}" == "lnd" ]; then
    echo "# LND Config"
    cat /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json | \
    jq ".port = \"${RTLHTTP}\"" | \
    jq ".multiPass = \"${RPCPASSWORD}\"" | \
    jq ".multiPassHashed = \"\"" | \
    jq ".nodes[0].lnNode = \"${hostname}\"" | \
    jq ".nodes[0].lnImplementation = \"LND\"" | \
    jq ".nodes[0].Authentication.macaroonPath = \"/home/rtl/.lnd/data/chain/${network}/${CHAIN}/\"" | \
    jq ".nodes[0].Authentication.configPath = \"/home/rtl/.lnd/${netprefix}lnd.conf\"" | \
    jq ".nodes[0].Authentication.swapMacaroonPath = \"/home/rtl/.loop/${CHAIN}/\"" | \
    jq ".nodes[0].Authentication.boltzMacaroonPath = \"/home/rtl/.boltz-lnd/macaroons/\"" | \
    jq ".nodes[0].Settings.userPersona = \"OPERATOR\"" | \
    jq ".nodes[0].Settings.lnServerUrl = \"https://localhost:${portprefix}8080\"" | \
    jq ".nodes[0].Settings.channelBackupPath = \"/mnt/hdd/app-data/rtl/${systemdService}-SCB-backup-$hostname\"" | \
    jq ".nodes[0].Settings.swapServerUrl = \"https://localhost:${SWAPSERVERPORT}\"" > /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json.tmp
    mv /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json.tmp /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json
  fi

  # C-Lightning changes of config
  # https://github.com/Ride-The-Lightning/RTL/blob/master/docs/C-Lightning-setup.md
  if [ "${LNTYPE}" == "cl" ]; then
    echo "# CL Config"
    cat /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json | \
    jq ".port = \"${RTLHTTP}\"" | \
    jq ".multiPass = \"${RPCPASSWORD}\"" | \
    jq ".multiPassHashed = \"\"" | \
    jq ".nodes[0].lnNode = \"${hostname}\"" | \
    jq ".nodes[0].lnImplementation = \"CLT\"" | \
    jq ".nodes[0].Authentication.macaroonPath = \"/home/bitcoin/c-lightning-REST/certs\"" | \
    jq ".nodes[0].Authentication.configPath = \"${CLCONF}\"" | \
    jq ".nodes[0].Authentication.swapMacaroonPath = \"/home/rtl/.loop/${CHAIN}/\"" | \
    jq ".nodes[0].Authentication.boltzMacaroonPath = \"/home/rtl/.boltz-lnd/macaroons/\"" | \
    jq ".nodes[0].Settings.userPersona = \"OPERATOR\"" | \
    jq ".nodes[0].Settings.lnServerUrl = \"https://localhost:${portprefix}6100\"" | \
    jq ".nodes[0].Settings.channelBackupPath = \"/mnt/hdd/app-data/rtl/${systemdService}-SCB-backup-$hostname\"" | \
    jq ".nodes[0].Settings.swapServerUrl = \"https://localhost:${SWAPSERVERPORT}\"" > /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json.tmp
    mv /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json.tmp /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json
  fi

  echo "# RTL prestart config done"
  exit 0
fi

##########################
# OFF
#########################

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # check that parameters are set
  if [ "${LNTYPE}" == "" ] || [ "${CHAIN}" == "" ]; then
    echo "# missing parameter"
    exit 1
  fi

  # stop services
  echo "# making sure services are not running"
  sudo systemctl stop ${systemdService} 2>/dev/null

  # remove config
  sudo rm -f /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set ${configEntry} "off"

  # remove nginx symlinks
  sudo rm -f /etc/nginx/sites-enabled/${netprefix}${typeprefix}rtl_ssl.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-enabled/${netprefix}${typeprefix}rtl_tor.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-enabled/${netprefix}${typeprefix}rtl_tor_ssl.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_ssl.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor_ssl.conf 2>/dev/null
  sudo nginx -t
  sudo systemctl reload nginx

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh off ${systemdService}
  fi

  isInstalled=$(sudo ls /etc/systemd/system/${systemdService}.service 2>/dev/null | grep -c "${systemdService}.service")
  if [ ${isInstalled} -eq 1 ]; then

    echo "# Removing RTL for ${LNTYPE} ${CHAIN}"
    sudo systemctl disable ${systemdService}.service
    sudo rm /etc/systemd/system/${systemdService}.service
    echo "# OK ${systemdService} removed."

  else
    echo "# ${systemdService} is not installed."
  fi

  # only if 'purge' is an additional parameter (other instances/services might need this)
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ];then
    echo "# Removing the binaries"
    echo "# Delete user and home directory"
    sudo userdel -rf rtl
    if [ $LNTYPE = cl ];then
      /home/admin/config.scripts/cl.rest.sh off ${CHAIN}
    fi
    echo "# Delete all configs"
    sudo rm -rf /mnt/hdd/app-data/rtl
  fi

  # close ports on firewall
  sudo ufw deny "${RTLHTTP}"
  sudo ufw deny $((RTLHTTP+1))
  exit 0
fi

# DEACTIVATED FOR NOW:
# - parameter scheme is conflicting with setting all prefixes etc
# - also just updating to latest has high change of breaking
#if [ "$1" = "update" ]; then
#  echo "# UPDATING RTL"
#  cd /home/rtl/RTL
#  updateOption="$2"
#  if [ ${#updateOption} -eq 0 ]; then
#    # from https://github.com/apotdevin/thunderhub/blob/master/scripts/updateToLatest.sh
#    # fetch latest master
#    sudo -u rtl git fetch
#    # unset $1
#    set --
#    UPSTREAM=${1:-'@{u}'}
#    LOCAL=$(git rev-parse @)
#    REMOTE=$(git rev-parse "$UPSTREAM")
#    if [ $LOCAL = $REMOTE ]; then
#      TAG=$(git tag | sort -V | tail -1)
#      echo "# You are up-to-date on version" $TAG
#    else
#      echo "# Pulling latest changes..."
#      sudo -u rtl git pull -p
#      echo "# Reset to the latest release tag"
#      TAG=$(git tag | sort -V | tail -1)
#      sudo -u rtl git reset --hard $TAG
#      echo "# updating to the latest"
#      # https://github.com/Ride-The-Lightning/RTL#or-update-existing-dependencies
#      sudo -u rtl npm install --only=prod
#      echo "# Updated to version" $TAG
#    fi
#  elif [ "$updateOption" = "commit" ]; then
#    echo "# updating to the latest commit in https://github.com/Ride-The-Lightning/RTL"
#    sudo -u rtl git pull -p
#    sudo -u rtl npm install --only=prod
#    currentRTLcommit=$(cd /home/rtl/RTL; git describe --tags)
#    echo "# Updated RTL to $currentRTLcommit"
#  else
#    echo "# Unknown option: $updateOption"
#  fi
#
#  echo
#  echo "# Starting the RTL service ... "
#  sudo systemctl start RTL
#  exit 0
#fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run normal again"
exit 1
