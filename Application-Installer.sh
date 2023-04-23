#!/bin/bash

function map_hostsfile_for_aws() { echo $(hostnamectl | grep -i static | awk '{print $3}' | sed 's/ip//g' | sed 's/.ec2.internal//g' | cut -c2- | sed 's/-/./g') $(hostnamectl | grep -i static | awk '{print $3}') >>/etc/hosts; }

#Populate /etc/hosts with parameters of on prem environment : LOCAL_IPADDRESS HOSTNAME
function map_hostfile_for_onprem() { echo $(hostnamectl | grep -i static | awk '{print $3}' | sed 's/-/./g' && hostnamectl | grep -i static | awk '{print $3}') >>/etc/hosts; }

# this function will determine if the application is already installed and exit if it is.
function is_application_installed() { if curl -k https://localhost:443 | grep 'Application welcome message' ||
  curl -k http://localhost:80 | grep 'Application welcome message'; then
  echo "Application is already installed and listening for connections! "
  exit 0
else
  echo "Application isn't installed starting installation process..."

fi; }

#need to modify selinux to change from enforcing to disabled
function modify_selinux() {
  echo "Disabling SELINUX"
  sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
  setenforce 0
}
# mount the application iso , iso name should be provided with full path
function mount_iso() {
  mkdir -p /tmp/mount
  echo "Please provide the full path to the ISO file:"
  read iso_path
  mount=$(mount -o loop $iso_path /tmp/mount)
  if [ "$?" -ne 0 ]; then
    echo "Failed to mount application ISO!, please provide full path to the Application ISO"
  else
    echo "Mounted application ISO successfully on /tmp/mount "
  fi
}

#remove postfix & mariadb packages
function find_remove_irrelevant() {
  check_postfix=$(rpm -qa | grep postfix)
  for line in 1; do
    echo -e "\n $check_postfix"
  done

  if [[ $check_postfix == *postfix* ]]; then
    for package in $check_postfix; do
      rpm -e $check_postfix
    done
  else
    echo "No postfix package found! skipping"
  fi

  check_mariadb=$(rpm -qa | grep mariadb)
  for line in 1; do
    echo -e "\n $check_mariadb"
  done

  if [[ $check_mariadb == *mariadb* ]]; then
    for mdbpackage in $check_mariadb; do
      rpm -e $check_mariadb
      echo "Removed all mariadb packages"
    done
  else
    echo "No mariadb packages found! skipping"
  fi
}

function prepare_mdb_env() {
  mkdir /root/mariadb-packages/
  cp /tmp/mount/Packages/mariadb* /root/mariadb-packages/
  cd /root/mariadb-packages/
  rm -rf *i686
  rm -rf mariadb-embedded-devel-1.1.41-2.el7_0.i686.rpm
  rpm -ivh mariadb-* --nodeps
}

#executing somescript
function execute_somescript() {
  ln -s / /mnt/sysimage
  /tmp/mount/somescript
}

#executing someotherscript
function execute_someotherscript() {
  cd /etc/application
  bash -x /etc/application
}

#populate mariadb with application databases  & tables
function populate_database() { cd /root/Application/ext && chmod 777 install_db.pl && ./install_db.pl; }

#determine if the OS resides in AWS or on prem and populate etc/hosts accordingly
function pouplate_etchosts() {
  echo "determining if instance is on prem or AWS"
  #if the hostnamectl commands find the string internal it means that the machine resides in AWS
  #otherwise this is an ON prem environment
  if hostnamectl | grep -i static | grep 'internal'; then
    echo "the machine resides under AWS, populating /etc/hosts accordingly"
    map_hostsfile_for_aws
  else
    echo "this is an on prem environment, populating  /etc/hosts accordingly"
    map_hostfile_for_onprem
  fi
}

#Run application installation  for cloud or on prem
function application_oncloud_or_not() { if hostnamectl | grep -i static | grep 'internal'; then
  echo "installing application in the cloud"
  cd /root/Application/someapp && ./app install

else
  echo "Installing someapp for On-Prem"
  cd /root/Application/someapp && ./app install
fi; }

#open listener on 443 (HTTPS) for httpd instead of 80 , application will no longer listen on port 80.
function enable_ssl() { cd /usr/local/application/ && bash -x ./change_to_ssl.sh; }

#restart Application services
function restart_application_services() {
  'systemctl restart Application ApplicationTS ApplicationRESTAPI mariadb httpd  elasticsearch'

ßß}

#determine if IP need to be modified to external IP in application configmaps
function modify_application_to_external_ip() { if hostnamectl | grep -i static | grep 'internal'; then
  external_ip=$(curl -s icanhazip.com)
  local_ip=$(hostnamectl | grep -i static | awk '{print $3}' | sed 's/ip//g' | sed 's/.ec2.internal//g' | cut -c2- | sed 's/-/./g')
  kubectl -n kube-system get cm someapplication1-name -o yaml | sed '1,/"parameter" : ":"/{s/"parameter" : ":"/"parameter" : "'"$external_ip"':999"/}' | kubectl replace -f -
  kubectl -n kube-system get cm someapplication1-name -o yaml | sed 's/'"$local_ip"':999"/'"$external_ip"':999"/g' | kubectl replace -f -
  kubectl -n kube-system get cm someapplication1-name -o yaml | sed 's/'"$local_ip"':999"/'"$external_ip"':999"/g' | kubectl replace -f -
  kubectl -n kube-system get sts someapplication1-kafka -o yaml | sed 's/'"$local_ip"':999/'"$external_ip"':999/g' | kubectl replace -f -
  kubectl -n kube-system delete pods --all --now
  echo "some components have been modified to work with external ip!"
  echo "Installation has finished, your environment is ready!"

else
  echo "Not a cloud environment application components will remain with internal IP"
  echo "Installation has finished your environment is ready!"

fi; }

is_application_installed
modify_selinux
mount_iso
find_remove_irrelevant
prepare_mdb_env
execute_somescript
execute_someotherscript
populate_database
pouplate_etchosts
application_oncloud_or_not
enable_ssl
restart_application_services
modify_application_to_external_ip
