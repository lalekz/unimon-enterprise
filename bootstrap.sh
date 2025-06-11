#!/bin/bash

set -e

if [ ! -x /bin/whiptail ]; then
    sudo apt install whiptail
fi

BACKTITLE="Unimon Enterprise Monitoring System installer"
DOCKER_VERSION=5:28.0.0-1~ubuntu.24.04~noble

function check_root()
{
  if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root, e.g. use sudo" >&2
    exit 1
  fi
}

function install_docker()
{
    # Add Docker's official GPG key:
    apt update
    apt install -y ca-certificates curl pwgen
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update

    apt install -y docker-ce=${DOCKER_VERSION} docker-ce-cli=${DOCKER_VERSION} containerd.io docker-buildx-plugin docker-compose-plugin

    whiptail --backtitle "$BACKTITLE" --msgbox "Docker has been succesfully installed" 8 78
}

function deploy_portainer()
{
    docker_passwd=$(whiptail --passwordbox "Enter Unimon Docker Registry password:" 8 40 3>&1 1>&2 2>&3)
    docker login --username unimon --password "${docker_passwd}" docker.unimon.ru

    docker network create -d bridge portainer_net ||:
    docker run -d --name portainer-agent --restart=always -p 9001:9001 --network=portainer_net \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v /var/lib/docker/volumes:/var/lib/docker/volumes \
      portainer/agent:2.20.3
    docker run --name portainer --restart=always -d -p 9000:9000 --network=portainer_net \
      -v /var/run/docker.sock:/var/run/docker.sock \
      docker.unimon.ru/portainer:2.20.3

    docker volume create certs ||:

    whiptail --backtitle "$BACKTITLE" --msgbox "Portainer has been succesfully deployed" 8 78
}

function install_chromium()
{
    apt update
    apt install -y chromium-browser
    whiptail --backtitle "$BACKTITLE" --msgbox "Chromium browser has been succesfully installed" 8 78
}

function gen_secrets()
{
    PUBLIC_PROTOCOL=http
    EMAIL_SERVER="ssl://"
    EMAIL_SERVER_PORT=465

    MYSQL_PASSWORD=$(pwgen -1 16)
    MYSQL_ROOT_PASSWORD=$(pwgen -1 16)
    INFLUXDB_ADMIN_PASSWORD=$(pwgen -1 16)
    INFLUXDB_USER_PASSWORD=$(pwgen -1 16)
    MOSQUITTO_SUPERUSER_PASSWORD=$(pwgen -1 16)
    RABBITMQ_DEFAULT_PASS=$(pwgen -1 16)
    API_SENDER_KEY=$(pwgen -1 32)
    declare `cat /proc/cpuinfo /proc/iomem | sha512sum | awk '{print "MINIO_ACCESS_KEY=" substr($1,1,24) "\nMINIO_SECRET_KEY=" substr($1,25,64) }'`

    if [ -e ./secrets.env ]; then
      whiptail --backtitle "$BACKTITLE" --yesno "Overwrite existing secrets.env file?" 8 78 || return 0
      . secrets.env
    fi


    PUBLIC_HOSTNAME=$(whiptail --inputbox "Enter hostname:" 8 40 $PUBLIC_HOSTNAME 3>&1 1>&2 2>&3)
    PUBLIC_PROTOCOL=$(whiptail --inputbox "Enter protocol:" 8 40 $PUBLIC_PROTOCOL 3>&1 1>&2 2>&3)
    EMAIL_SERVER=$(whiptail --inputbox "Enter email server:" 8 40 $EMAIL_SERVER 3>&1 1>&2 2>&3)
    EMAIL_SERVER_PORT=$(whiptail --inputbox "Enter email server port:" 8 40 $EMAIL_SERVER_PORT 3>&1 1>&2 2>&3)
    EMAIL_SERVER_USER=$(whiptail --inputbox "Enter email server username:" 8 40 $EMAIL_SERVER_USER 3>&1 1>&2 2>&3)
    EMAIL_SERVER_PASSWORD=$(whiptail --inputbox "Enter email server password:" 8 40 $EMAIL_SERVER_PASSWORD 3>&1 1>&2 2>&3)

    {
        echo "PUBLIC_HOSTNAME=${PUBLIC_HOSTNAME}"
        echo "PUBLIC_PROTOCOL=${PUBLIC_PROTOCOL}"
        echo "EMAIL_SERVER=${EMAIL_SERVER}"
        echo "EMAIL_SERVER_PORT=${EMAIL_SERVER_PORT}"
        echo "EMAIL_SERVER_FROM=${EMAIL_SERVER_USER}"
        echo "EMAIL_SERVER_USER=${EMAIL_SERVER_USER}"
        echo "EMAIL_SERVER_PASSWORD=${EMAIL_SERVER_PASSWORD}"
        echo "MYSQL_PASSWORD=${MYSQL_PASSWORD}"
        echo "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}"
        echo "INFLUXDB_ADMIN_PASSWORD=${INFLUXDB_ADMIN_PASSWORD}"
        echo "INFLUXDB_USER_PASSWORD=${INFLUXDB_USER_PASSWORD}"
        echo "MOSQUITTO_SUPERUSER_PASSWORD=${MOSQUITTO_SUPERUSER_PASSWORD}"
        echo "RABBITMQ_DEFAULT_PASS=${RABBITMQ_DEFAULT_PASS}"
        echo "API_SENDER_KEY=${API_SENDER_KEY}"
        echo "MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY}"
        echo "MINIO_SECRET_KEY=${MINIO_SECRET_KEY}"
    } >secrets.env

    whiptail --backtitle "$BACKTITLE" --title "secrets.env" --textbox --scrolltext secrets.env 25 100
}

case "$1" in
    install_docker )
        check_root
        install_docker
        exit 0
    ;;
    deploy_portainer )
        check_root
        deploy_portainer
        exit 0
    ;;
    install_chromium )
        check_root
        install_chromium
        exit 0
    ;;
    gen_secrets )
        gen_secrets
        exit 0
    ;;
esac

while (true); do

    tool=$(whiptail --backtitle "$BACKTITLE" --menu "Choose an action" 25 78 5 \
        1 "Install Docker" \
        2 "Deploy Portainer" \
        3 "Install Chromium Browser" \
        4 "Generate secrets" 3>&1 1>&2 2>&3)

    case $tool in
        1 )
            sudo $0 install_docker
        ;;
        2 )
            sudo $0 deploy_portainer
        ;;
        3 )
            sudo $0 install_chromium
        ;;
        4 )
            gen_secrets
        ;;
    esac

done
