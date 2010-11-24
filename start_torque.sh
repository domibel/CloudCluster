#!/bin/bash
#
# Copyright 2010 Dominique Belhachemi
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# uncomment the following line to enable debugging
set -ex


usage()
{
    cat << EOF

usage: $0 options

This script starts the torque environment.

OPTIONS:

   -h | --help             Show this message
   -n | --torque-nodes     worker nodes ip              e.g. "192.168.0.14,192.168.0.14"
   -s | --torque-server    torque head node ip          e.g. "192.168.0.13"
   -k | --key              key file
   -v | --verbose          verbose mode
   -m | --with-mpi         with MPI support
        --nfs-server       NFS server

example: start_torque.sh --nfs-server="184.72.202.37" -s="184.72.202.37" -n="50.16.45.7,184.72.143.16" -k=/home/user/user.pem
EOF
}


function get_hostname_from_ip {
    IP=$1
    HOSTNAME=`nslookup $IP | grep "name =" | awk '{print $4}'`
    # remove the trailing . from HOSTNAME (I get this from nslookup)
    HOSTNAME=${HOSTNAME%.}
    return 0
}

function get_ip_from_hostname {
    HOSTNAME=$1
    IP=`nslookup $HOSTNAME | grep Address | grep -v '#' | cut -f 2 -d ' '`
    return 0
}

function apt_update {
    $SUDO apt-get -o Dpkg::Options::="--force-confnew" --force-yes -y update
    if [ $? -ne 0 ] ; then
        echo "aptitude update failed"
    fi
}

function install_package {
    PACKAGE=$1

    if [ "`dpkg-query -W -f='${Status}\n' $PACKAGE`" != "install ok installed" ] ; then
        $SUDO apt-get -o Dpkg::Options::="--force-confnew" --force-yes -y install $PACKAGE
        #aptitude -y install $PACKAGE
        if [ $? -ne 0 ] ; then
            echo "aptitude install $PACKAGE failed"
        fi
    else
        echo "package $PACKAGE is already installed"
    fi
}



# default
VERBOSE=0
IN_INSTANCE=0
MPI=0

# For Debian
SUPERUSER=root
SUDO=

# For Ubuntu
#SUPERUSER=ubuntu
#SUDO=sudo

OverwriteDNS=0

#e.g. guest, ubuntu
OTHERUSER=guest

UseAmazonEucalyptus=1


# values are "public" and "private"
INTERFACE="private"

DEBUG=1

if [ $UseAmazonEucalyptus -eq 1 ]; then
    echo Script running on `hostname` : `/sbin/ifconfig eth0 | grep "inet addr" | awk '{print $2}' | sed 's/addr\://'` \(Amazon/Eucalyptus\)
else
    echo Script running on `hostname` : `/sbin/ifconfig vboxnet0 | grep "inet addr" | awk '{print $2}' | sed 's/addr\://'` \(VirtualBox\)
fi


# if in instance
kernel=`uname -r`
if [[ $kernel == *xen* ]]; then
    apt_update
    # this is needed in each instance, for nslookup
    install_package dnsutils
fi

# parse arguments
for i in $*
do
    case $i in
        -s=*|--torque-server=*)
            # remove option from string
            OPTION_S=`echo $i | sed 's/[-a-zA-Z0-9]*=//'`

            # for now provide only IPs, TODO: is_valid_IP($OPTION_S)
            if [ 1 ] ; then
                TORQUE_HEAD_NODE_PUBLIC_IP=$OPTION_S
                get_hostname_from_ip $TORQUE_HEAD_NODE_PUBLIC_IP
                TORQUE_HEAD_NODE_PUBLIC_HOSTNAME=$HOSTNAME
            else
                TORQUE_HEAD_NODE_PUBLIC_HOSTNAME=$OPTION_S
                get_ip_from_hostname $TORQUE_HEAD_NODE_PUBLIC_HOSTNAME
                TORQUE_HEAD_NODE_PUBLIC_IP=$IP
            fi
            echo TORQUE_HEAD_NODE_PUBLIC_INTERFACE: $TORQUE_HEAD_NODE_PUBLIC_IP $TORQUE_HEAD_NODE_PUBLIC_HOSTNAME
            ;;
        -n=*|--torque-nodes=*)
            # remove option from string
            OPTION_N=`echo $i | sed 's/[-a-zA-Z0-9]*=//'`
            PUBLIC_TORQUE_NODES=`echo $OPTION_N | sed 's/\,/ /g'`
            for PUBLIC_TORQUE_NODE in `echo $PUBLIC_TORQUE_NODES`
            do
                # for now provide only IPs, TODO: is_valid_IP($OPTION_S)
                if [ 1 ] ; then
                    TORQUE_WORKER_NODE_PUBLIC_IP=$PUBLIC_TORQUE_NODE
                    get_hostname_from_ip $TORQUE_WORKER_NODE_PUBLIC_IP
                    TORQUE_WORKER_NODE_PUBLIC_HOSTNAME=$HOSTNAME
                else
                    TORQUE_WORKER_NODE_PUBLIC_HOSTNAME=$PUBLIC_TORQUE_NODE
                    get_ip_from_hostname $TORQUE_WORKER_NODE_PUBLIC_HOSTNAME
                    TORQUE_WORKER_NODE_PUBLIC_IP=$IP
                fi
                echo TORQUE_WORKER_NODE_PUBLIC_IP: $TORQUE_WORKER_NODE_PUBLIC_IP
                echo TORQUE_WORKER_NODE_PUBLIC_HOSTNAME: $TORQUE_WORKER_NODE_PUBLIC_HOSTNAME
                TORQUE_WORKER_NODES_PUBLIC_IP="$TORQUE_WORKER_NODES_PUBLIC_IP $TORQUE_WORKER_NODE_PUBLIC_IP"
                TORQUE_WORKER_NODES_PUBLIC_HOSTNAME="$TORQUE_WORKER_NODES_PUBLIC_HOSTNAME $TORQUE_WORKER_NODE_PUBLIC_HOSTNAME"
            done
            echo TORQUE_WORKER_NODES_PUBLIC_IP: $TORQUE_WORKER_NODES_PUBLIC_IP
            echo TORQUE_WORKER_NODES_PUBLIC_HOSTNAME: $TORQUE_WORKER_NODES_PUBLIC_HOSTNAME
            ;;
        -k=*|--key=*)
            # remove option from string
            KEY=`echo $i | sed 's/[-a-zA-Z0-9]*=//'`
            echo $KEY
            ;;
        --verbose)
            VERBOSE=1
            ;;
        -i|--in-instance)
            IN_INSTANCE=1
            ;;
        -m=*|--with-mpi=*)
            MPI=`echo $i | sed 's/[-a-zA-Z0-9]*=//'`
            ;;
        --nfs-server=*)
            NFS_SERVER_PUBLIC_IP=`echo $i | sed 's/[-a-zA-Z0-9]*=//'`
            get_hostname_from_ip $NFS_SERVER_PUBLIC_IP
            NFS_SERVER_PUBLIC_HOSTNAME=$HOSTNAME
            ;;
        *)
            echo "unknown option"
            ;;
    esac
done


if [[ -z $TORQUE_WORKER_NODES_PUBLIC_IP ]] || [[ -z $TORQUE_HEAD_NODE_PUBLIC_IP ]]
then
    usage
    exit 1
fi



# join torque head node and torque worker nodes
if [[ $TORQUE_WORKER_NODES_PUBLIC_IP == *$TORQUE_HEAD_NODE_PUBLIC_IP* ]]
then
    TORQUE_NODES_PUBLIC_IP="$TORQUE_WORKER_NODES_PUBLIC_IP"
    TORQUE_NODES_PUBLIC_HOSTNAME="$TORQUE_WORKER_NODES_PUBLIC_HOSTNAME"
else
    TORQUE_NODES_PUBLIC_IP="$TORQUE_HEAD_NODE_PUBLIC_IP $TORQUE_WORKER_NODES_PUBLIC_IP"
    TORQUE_NODES_PUBLIC_HOSTNAME="$TORQUE_HEAD_NODE_PUBLIC_HOSTNAME $TORQUE_WORKER_NODES_PUBLIC_HOSTNAME"
fi
echo TORQUE_NODES_PUBLIC_IP: $TORQUE_NODES_PUBLIC_IP
echo TORQUE_NODES_PUBLIC_HOSTNAME: $TORQUE_NODES_PUBLIC_HOSTNAME

# BEGIN execution on master #################################################
if [ $IN_INSTANCE -eq 0 ] ; then

    # start NFS server first, TODO this is copy and paste from below

    # make this host known to ~/.ssh/known_hosts on master
    ssh -i $KEY -o StrictHostKeychecking=no $SUPERUSER@$NFS_SERVER_PUBLIC_IP echo private hostname: '`hostname`'

    # copy main script to instance
    scp -p -i $KEY start_torque.sh $SUPERUSER@$NFS_SERVER_PUBLIC_IP:~/

    if [ $MPI == 1 ] ; then
        # copy test mpi script to instance
        scp -p -i $KEY compileMPI.sh helloworld.c $SUPERUSER@$NFS_SERVER_PUBLIC_IP:~/
    fi

    INST_TORQUE_WORKER_NODES_PUBLIC_IP=`echo $TORQUE_WORKER_NODES_PUBLIC_IP | sed 's/ /\,/g'`
    ssh -X -i $KEY $SUPERUSER@$NFS_SERVER_PUBLIC_IP "~/start_torque.sh" -s=\"$TORQUE_HEAD_NODE_PUBLIC_IP\" -n=\"$INST_TORQUE_WORKER_NODES_PUBLIC_IP\" -i -m=$MPI --nfs-server="$NFS_SERVER_PUBLIC_IP"


    # copy setup-torque-script to TORQUE nodes
    for TORQUE_NODE_PUBLIC_IP in `echo $TORQUE_NODES_PUBLIC_IP`
    do
        echo $TORQUE_NODE_PUBLIC_IP

        # make this host known to ~/.ssh/known_hosts on master
        ssh -i $KEY -o StrictHostKeychecking=no $SUPERUSER@$TORQUE_NODE_PUBLIC_IP echo private hostname: '`hostname`'

        # copy main script to instance
        scp -p -i $KEY start_torque.sh $SUPERUSER@$TORQUE_NODE_PUBLIC_IP:~/

        if [ $MPI == 1 ] ; then
            # copy test mpi script to instance
            scp -p -i $KEY compileMPI.sh helloworld.c $SUPERUSER@$TORQUE_NODE_PUBLIC_IP:~/
        fi

        # execute main script in instance to setup torque, TODO, this list is a comma separated list, I should improve it
        INST_TORQUE_WORKER_NODES_PUBLIC_IP=`echo $TORQUE_WORKER_NODES_PUBLIC_IP | sed 's/ /\,/g'`
        ssh -X -i $KEY $SUPERUSER@$TORQUE_NODE_PUBLIC_IP "~/start_torque.sh" -s=\"$TORQUE_HEAD_NODE_PUBLIC_IP\" -n=\"$INST_TORQUE_WORKER_NODES_PUBLIC_IP\" -i -m=$MPI --nfs-server="$NFS_SERVER_PUBLIC_IP"
    done


    #### The script above added all necessary user to all nodes, now the keys can be distributed

    for TORQUE_NODE_PUBLIC_IP in `echo $TORQUE_NODES_PUBLIC_IP`
    do
        # execute to generate keys in instances - for user $OTHERUSER
        ssh -X -i $KEY $SUPERUSER@$TORQUE_NODE_PUBLIC_IP "bash ~/keygen_in_instance.sh" #TODO
    done


    for SRC_TORQUE_NODE_PUBLIC_IP in `echo $TORQUE_NODES_PUBLIC_IP`
    do
        # distribute this key to all other nodes
        for DST_TORQUE_NODE_PUBLIC_IP in `echo $TORQUE_NODES_PUBLIC_IP`
        do
            echo $DST_TORQUE_NODE_PUBLIC_IP

            # copy from src to dst
            scp -p -i $KEY $SUPERUSER@$SRC_TORQUE_NODE_PUBLIC_IP:/home/$OTHERUSER/.ssh/id_rsa.pub /tmp/id_rsa.pub

            # direct copy from src to dst not possible, why not?
            scp -p -i $KEY /tmp/id_rsa.pub $SUPERUSER@$DST_TORQUE_NODE_PUBLIC_IP:/tmp/id_rsa.pub

            ssh -X -i $KEY $SUPERUSER@$DST_TORQUE_NODE_PUBLIC_IP "cat /tmp/id_rsa.pub | $SUDO tee -a /home/$OTHERUSER/.ssh/authorized_keys"

        done
        #execute, connect to other server generate entry in known_hosts of $OTHERUSER
        ssh -X -i $KEY $SUPERUSER@$SRC_TORQUE_NODE_PUBLIC_IP /tmp/hosts.sh
    done


    # on master don't execute commands for instances
    exit 0
fi
# END   execution on master #################################################











# BEGIN execution in instance ###############################################

echo in instance : `hostname`

# generate script
cat > keygen_in_instance.sh << EOF
#!/bin/bash
#$SUDO -u $OTHERUSER mkdir -p /home/$OTHERUSER/.ssh/
su $OTHERUSER -c 'mkdir -p /home/$OTHERUSER/.ssh/'
if [ ! -f /home/$OTHERUSER/.ssh/id_rsa ]; then
    #$SUDO -u $OTHERUSER ssh-keygen -t rsa -N "" -f /home/$OTHERUSER/.ssh/id_rsa
    su $OTHERUSER -c 'ssh-keygen -t rsa -N "" -f /home/$OTHERUSER/.ssh/id_rsa'
fi
EOF
chmod 755 keygen_in_instance.sh


export DEBIAN_FRONTEND="noninteractive"
export APT_LISTCHANGES_FRONTEND="none"
CURL="/usr/bin/curl"

#API_VERSION="2008-02-01"
#METADATA_URL="http://169.254.169.254/$API_VERSION/meta-data"

METADATA_URL="http://169.254.169.254/latest/meta-data/"

# those variables are needed for the locales package
export LANGUAGE=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# for dialog frontend
export PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin
export TERM=linux

DATE=`date '+%Y%m%d'`
NUMBER_PROCESSORS=`cat /proc/cpuinfo | grep processor | wc -l`
NUMBER_PROCESSORS=2 #TODO

# clean-up
$SUDO dpkg --configure -a


# install lsb-release
install_package lsb-release

# get some information about the Operating System
DISTRIBUTOR=`lsb_release -i | awk '{print $3}'`
CODENAME=`lsb_release -c | awk '{print $2}'`
echo $DISTRIBUTOR $CODENAME


# for Eucalyptus if hostnames are not set properly
if [ $OverwriteDNS -eq 1 ] ; then
    TORQUE_HEAD_NODE_PUBLIC_HOSTNAME=ip-`echo $TORQUE_HEAD_NODE_PUBLIC_IP | sed 's/\./-/g'`
    echo TORQUE_HEAD_NODE_PUBLIC_INTERFACE: $TORQUE_HEAD_NODE_PUBLIC_IP $TORQUE_HEAD_NODE_PUBLIC_HOSTNAME

    TORQUE_HEAD_NODE_PRIVATE_HOSTNAME=ip-`echo $TORQUE_HEAD_NODE_PRIVATE_IP | sed 's/\./-/g'`
    echo TORQUE_HEAD_NODE_PRIVATE_INTERFACE: $TORQUE_HEAD_NODE_PRIVATE_IP $TORQUE_HEAD_NODE_PRIVATE_HOSTNAME

    INSTANCE_PUBLIC_IP=`/sbin/ifconfig eth0 | grep "inet addr" | awk '{print $2}' | sed 's/addr\://'`
    INSTANCE_PUBLIC_HOSTNAME=ip-`echo $INSTANCE_PUBLIC_IP | sed 's/\./-/g'`
    INSTANCE_PRIVATE_HOSTNAME=ip-`echo $INSTANCE_PRIVATE_IP | sed 's/\./-/g'`
fi



# get private interface IP and HOSTNAME from NFS server
get_ip_from_hostname $NFS_SERVER_PUBLIC_HOSTNAME
NFS_SERVER_PRIVATE_IP=$IP
get_hostname_from_ip $NFS_SERVER_PRIVATE_IP
NFS_SERVER_PRIVATE_HOSTNAME=$HOSTNAME
echo NFS_SERVER_PRIVATE_INTERFACE: $NFS_SERVER_PRIVATE_IP $NFS_SERVER_PRIVATE_HOSTNAME


# get private interface IP and HOSTNAME from Torque server
get_ip_from_hostname $TORQUE_HEAD_NODE_PUBLIC_HOSTNAME
TORQUE_HEAD_NODE_PRIVATE_IP=$IP
get_hostname_from_ip $TORQUE_HEAD_NODE_PRIVATE_IP
TORQUE_HEAD_NODE_PRIVATE_HOSTNAME=$HOSTNAME
echo TORQUE_HEAD_NODE_PRIVATE_INTERFACE: $TORQUE_HEAD_NODE_PRIVATE_IP $TORQUE_HEAD_NODE_PRIVATE_HOSTNAME

# get private interface IPs and HOSTNAMEs from Nodes
for TORQUE_WORKER_NODE_PUBLIC_HOSTNAME in `echo $TORQUE_WORKER_NODES_PUBLIC_HOSTNAME`
do
    get_ip_from_hostname $TORQUE_WORKER_NODE_PUBLIC_HOSTNAME
    TORQUE_WORKER_NODE_PRIVATE_IP=$IP
    get_hostname_from_ip $TORQUE_WORKER_NODE_PRIVATE_IP
    TORQUE_WORKER_NODE_PRIVATE_HOSTNAME=$HOSTNAME
    echo TORQUE_WORKER_NODE_PRIVATE_INTERFACE: $TORQUE_WORKER_NODE_PRIVATE_IP $TORQUE_WORKER_NODE_PRIVATE_HOSTNAME

    # add to list
    TORQUE_WORKER_NODES_PRIVATE_IP="$TORQUE_WORKER_NODES_PRIVATE_IP $TORQUE_WORKER_NODE_PRIVATE_IP"
    TORQUE_WORKER_NODES_PRIVATE_HOSTNAME="$TORQUE_WORKER_NODES_PRIVATE_HOSTNAME $TORQUE_WORKER_NODE_PRIVATE_HOSTNAME"
done
echo TORQUE_WORKER_NODES_PRIVATE_INTERFACE: $TORQUE_WORKER_NODES_PRIVATE_IP $TORQUE_WORKER_NODES_PRIVATE_HOSTNAME

# join server and nodes
if [[ $TORQUE_WORKER_NODES_PRIVATE_IP == *$TORQUE_HEAD_NODE_PRIVATE_IP* ]]
then
    TORQUE_NODES_PRIVATE_IP="$TORQUE_WORKER_NODES_PRIVATE_IP"
    TORQUE_NODES_PRIVATE_HOSTNAME="$TORQUE_WORKER_NODES_PRIVATE_HOSTNAME"
else
    TORQUE_NODES_PRIVATE_IP="$TORQUE_HEAD_NODE_PRIVATE_IP $TORQUE_WORKER_NODES_PRIVATE_IP"
    TORQUE_NODES_PRIVATE_HOSTNAME="$TORQUE_HEAD_NODE_PRIVATE_HOSTNAME $TORQUE_WORKER_NODES_PRIVATE_HOSTNAME"
fi
echo TORQUE_NODES_PRIVATE_IP: $TORQUE_NODES_PRIVATE_IP
echo TORQUE_NODES_PRIVATE_HOSTNAME: $TORQUE_NODES_PRIVATE_HOSTNAME


# get instance information
INSTANCE_PUBLIC_IP=`curl -s $METADATA_URL/public-ipv4`
INSTANCE_PUBLIC_HOSTNAME=`curl -s $METADATA_URL/public-hostname`
echo $INSTANCE_PUBLIC_IP $INSTANCE_PUBLIC_HOSTNAME

INSTANCE_PRIVATE_IP=`/sbin/ifconfig eth0 | grep "inet addr" | awk '{print $2}' | sed 's/addr\://'`
get_hostname_from_ip $TORQUE_HEAD_NODE_PRIVATE_IP
INSTANCE_PRIVATE_HOSTNAME=$HOSTNAME
echo $INSTANCE_PRIVATE_IP $INSTANCE_PRIVATE_HOSTNAME


#using PUBLIC or PRIVATE interface
if [ $INTERFACE == "public" ] ; then
    INSTANCE_IP=$INSTANCE_PUBLIC_IP
    INSTANCE_HOSTNAME=$INSTANCE_PUBLIC_HOSTNAME
    TORQUE_HEAD_NODE_IP=$TORQUE_HEAD_NODE_PUBLIC_IP
    TORQUE_HEAD_NODE_HOSTNAME=$TORQUE_HEAD_NODE_PUBLIC_HOSTNAME
    NFS_SERVER_IP=$NFS_SERVER_PUBLIC_IP
    NFS_SERVER_HOSTNAME=$NFS_SERVER_PUBLIC_HOSTNAME
    TORQUE_WORKER_NODES_IP=$TORQUE_WORKER_NODES_PUBLIC_IP
    TORQUE_WORKER_NODES_HOSTNAME=$TORQUE_WORKER_NODES_PUBLIC_HOSTNAME
    TORQUE_NODES_IP=$TORQUE_NODES_PUBLIC_IP
    TORQUE_NODES_HOSTNAME=$TORQUE_NODES_PUBLIC_HOSTNAME
else
    if [ $INTERFACE == "private" ] ; then
        INSTANCE_IP=$INSTANCE_PRIVATE_IP
        INSTANCE_HOSTNAME=$INSTANCE_PRIVATE_HOSTNAME
        TORQUE_HEAD_NODE_IP=$TORQUE_HEAD_NODE_PRIVATE_IP
        TORQUE_HEAD_NODE_HOSTNAME=$TORQUE_HEAD_NODE_PRIVATE_HOSTNAME
        NFS_SERVER_IP=$NFS_SERVER_PRIVATE_IP
        NFS_SERVER_HOSTNAME=$NFS_SERVER_PRIVATE_HOSTNAME
        TORQUE_WORKER_NODES_IP=$TORQUE_WORKER_NODES_PRIVATE_IP
        TORQUE_WORKER_NODES_HOSTNAME=$TORQUE_WORKER_NODES_PRIVATE_HOSTNAME
        TORQUE_NODES_IP=$TORQUE_NODES_PRIVATE_IP
        TORQUE_NODES_HOSTNAME=$TORQUE_NODES_PRIVATE_HOSTNAME
    else
        echo "please specify private or public interface"
    fi
fi


## add user to all nodes
if id $OTHERUSER > /dev/null 2>&1
then
    echo "user exist!"
else
    $SUDO adduser $OTHERUSER --disabled-password --gecos ""
fi


# for torque on Ubuntu
if [ $DISTRIBUTOR == Ubuntu ] ; then
    echo "deb http://us-east-1.ec2.archive.ubuntu.com/ubuntu/ $CODENAME multiverse" | $SUDO tee -a /etc/apt/sources.list
fi

# for torque on Debian lenny
if [ $DISTRIBUTOR == Debian ] && [ $CODENAME == lenny ] ; then
    if ! egrep -q "lenny-backports" /etc/apt/sources.list ; then
        echo "deb http://backports.debian.org/debian-backports lenny-backports main" | $SUDO tee -a /etc/apt/sources.list
    fi
fi

#echo "deb http://ftp.us.debian.org/debian sid main" > /etc/apt/sources.list
#echo "deb http://ftp.us.debian.org/debian squeeze main" > /etc/apt/sources.list
#echo "deb http://security.debian.org/ squeeze/updates main" >> /etc/apt/sources.list

# update package source information
apt_update

# get rid of some error messages because of missing locales package
install_package locales
$SUDO rm -f /etc/locale.gen
echo "en_US.UTF-8 UTF-8" | $SUDO tee -a /etc/locale.gen
$SUDO locale-gen


if [ $DEBUG == 1 ] ; then
    # install nmap
    install_package nmap
    nmap localhost -p 1-20000
fi

# install ntpdate
install_package ntpdate
###$SUDO ntpdate pool.ntp.org
$SUDO ntpdate ntp.ubuntu.com


# make hostnames known to all the TORQUE nodes and server/scheduler
if [ $OverwriteDNS -eq 1 ] ; then
    #TODO
    if [ $INTERFACE == "private" ] ; then
        for NODE_IP in `echo $PRIVATE_NODES_IP`
        do
            NODE_HOSTNAME=ip-`echo $NODE_IP | sed 's/\./-/g'`
            echo "$NODE_IP   $NODE_HOSTNAME" >> /etc/hosts
        done
    fi


    if [ $INTERFACE == "public" ] ; then
        for NODE_IP in `echo $PUBLIC_NODES_IP`
        do
            NODE_HOSTNAME=ip-`echo $NODE_IP | sed 's/\./-/g'`
            if [ $INSTANCE_IP != $TORQUE_HEAD_NODE_IP ] || [ $NODE_IP != $TORQUE_HEAD_NODE_IP ]; then
                if ! egrep -q "$NODE_IP|$NODE_HOSTNAME" /etc/hosts ; then
                    echo "$NODE_IP   $NODE_HOSTNAME" >> /etc/hosts
                fi
            fi
        done
    fi

    # on TORQUE server
    if [ $INSTANCE_IP == $TORQUE_HEAD_NODE_IP ]; then
        #this one is for the scheduler, if using the public interface
        if ! egrep -q "127.0.1.1|$INSTANCE_PUBLIC_HOSTNAME" /etc/hosts ; then
            echo "127.0.1.1 $INSTANCE_PUBLIC_HOSTNAME" >> /etc/hosts
        fi

    #echo "$INSTANCE_PRIVATE_IP $INSTANCE_PRIVATE_HOSTNAME" >> /etc/hosts
    else
        if ! egrep -q "$TORQUE_HEAD_NODE_IP|$TORQUE_HEAD_NODE_HOSTNAME" /etc/hosts ; then
            echo "$TORQUE_HEAD_NODE_IP $TORQUE_HEAD_NODE_HOSTNAME" >> /etc/hosts
        fi
    fi

    # need to set a hostname before installing torque packages
    $SUDO rm -f /etc/hostname
    echo $INSTANCE_HOSTNAME | tee -a /etc/hostname # preserve hostname if rebooting is necessary
    $SUDO hostname $INSTANCE_HOSTNAME # immediately change
    #getent hosts `hostname`
    #INSTANCE_PUBLIC_HOSTNAME=`curl -s $METADATA_URL/public-hostname`
fi


# on all TORQUE worker nodes
if [[ $TORQUE_WORKER_NODES_IP == *$INSTANCE_IP* ]] ; then

    # install portmap for NFS
    install_package portmap
    install_package nfs-common

    # install OpenMPI packages
    #if [ $MPI == 1 ] ; then
    #    install_package "linux-headers-2.6.35-22-virtual"
    #fi

    # install OpenMPI packages
    if [ $MPI == 1 ] ; then
        install_package "libopenmpi-dev"
        install_package "openmpi-bin"

        #compile MPI test program
        bash compileMPI.sh
    fi
fi


# on TORQUE head node
if [ $INSTANCE_IP == $TORQUE_HEAD_NODE_IP ]; then
    install_package "torque-server torque-scheduler torque-client"
fi


# on TORQUE worker node
if [[ $TORQUE_WORKER_NODES_IP == *$INSTANCE_IP* ]]; then
    install_package "torque-mom torque-client"
fi


# on NFS server
if [ $INSTANCE_IP == $NFS_SERVER_IP ]; then
    install_package "nfs-kernel-server"
fi


# on NFS server
if [ $INSTANCE_IP == $NFS_SERVER_IP ]; then

    $SUDO mkdir -p /data
    $SUDO mkdir -p /data/test
    $SUDO chmod -R 777 /data
    $SUDO rm -f /etc/exports
    $SUDO touch /etc/exports
    # export to TORQUE head node and all TORQUE worker nodes
    for TORQUE_NODE_IP in `echo $TORQUE_NODES_IP`
    do
        echo -ne "/data $TORQUE_NODE_IP(rw,sync,no_subtree_check)\n" | $SUDO tee -a /etc/exports
    done
    $SUDO exportfs -ar
fi


# on all TORQUE nodes (head node + worker nodes)
if [[ $TORQUE_NODES_IP == *$INSTANCE_IP* ]] ; then

    # create script to distribute host keys
    rm -f /tmp/hosts.sh
    for TORQUE_NODE_IP in `echo $TORQUE_NODES_IP`
    do
        echo "($SUDO su - $OTHERUSER -c \"ssh -t -t -o StrictHostKeychecking=no $OTHERUSER@$TORQUE_NODE_IP echo ''\")& wait" >> /tmp/hosts.sh
    done
    # torque is communicating via the hostname
    for TORQUE_NODE_HOSTNAME in `echo $TORQUE_NODES_HOSTNAME`
    do
        echo "($SUDO su - $OTHERUSER -c \"ssh -t -t -o StrictHostKeychecking=no $OTHERUSER@$TORQUE_NODE_HOSTNAME echo ''\")& wait" >> /tmp/hosts.sh
    done
    chmod 755 /tmp/hosts.sh

    #TORQUE
    $SUDO rm -f /etc/torque/server_name
    echo $TORQUE_HEAD_NODE_HOSTNAME | $SUDO tee -a /etc/torque/server_name

    #NFS
    if ! egrep -q "$NFS_SERVER_PRIVATE_IP" /etc/fstab ; then
        echo -ne "$NFS_SERVER_PRIVATE_IP:/data  /mnt/data  nfs  defaults  0  0\n" | $SUDO tee -a /etc/fstab
    fi
    $SUDO mkdir -p /mnt/data
    # umount, ignore return code
    echo `$SUDO umount /mnt/data -v`
    $SUDO mount /mnt/data -v

    # if you don't create this file you will get errors like:
    # qsub: Bad UID for job execution MSG=ruserok failed validating guest/guest from domU-12-31-38-04-1D-C5.compute-1.internal
    $SUDO rm -f /etc/hosts.equiv
    $SUDO touch /etc/hosts.equiv
    for TORQUE_WORKER_NODE_HOSTNAME in `echo $TORQUE_WORKER_NODES_HOSTNAME`
    do
        if ! egrep -q "$TORQUE_WORKER_NODE_HOSTNAME" /etc/hosts.equiv ; then
            echo -ne "$TORQUE_WORKER_NODE_HOSTNAME\n" | $SUDO tee -a /etc/hosts.equiv
        fi
    done
fi


# on TORQUE worker nodes
if [[ $TORQUE_WORKER_NODES_IP == *$INSTANCE_IP* ]]; then

    if [ $MPI -eq 1 ] ; then
        $SUDO mkdir -p /etc/torque
        $SUDO rm -f /etc/torque/hostfile
        $SUDO touch /etc/torque/hostfile
        for TORQUE_WORKER_NODE_HOSTNAME in `echo $TORQUE_WORKER_NODES_HOSTNAME`
        do
            if ! egrep -q "$TORQUE_WORKER_NODE_HOSTNAME" /etc/torque/hostfile ; then
                # todo: numer_procs?
                echo "$TORQUE_WORKER_NODE_HOSTNAME slots=1" | $SUDO tee -a /etc/torque/hostfile
            fi
        done
    fi

    # kill running process
    if [ ! -z "$(pgrep pbs_mom)" ] ; then
        echo `$SUDO killall -s KILL pbs_mom`
    fi

    # get rid of old logs
    $SUDO rm -f /var/spool/torque/mom_logs/*

    # create new configuration
    $SUDO rm -f /var/spool/torque/mom_priv/config
    echo "\$timeout 120" | $SUDO tee -a /var/spool/torque/mom_priv/config # more options possible (NFS...)
    echo "\$loglevel 5"  | $SUDO tee -a /var/spool/torque/mom_priv/config # more options possible (NFS...)

    # try to start torque-mom (pbs_mom) up to 3 times
    for i in {1..3}
    do
        if [ -z "$(pgrep pbs_mom)" ] ; then
            # pbs_mom is not running
            $SUDO /etc/init.d/torque-mom start
            sleep 1
        else
            # pbs_mom is running
            break
        fi
    done

    # debug
    $SUDO touch /var/spool/torque/mom_logs/$DATE
    $SUDO cat /var/spool/torque/mom_logs/$DATE
fi


# on TORQUE head node
if [ $INSTANCE_IP == $TORQUE_HEAD_NODE_IP ]; then

    #TORQUE server
    $SUDO rm -f /var/spool/torque/server_priv/nodes
    $SUDO touch /var/spool/torque/server_priv/nodes
    for TORQUE_WORKER_NODE_HOSTNAME in `echo $TORQUE_WORKER_NODES_HOSTNAME`
    do
        echo -ne "$TORQUE_WORKER_NODE_HOSTNAME np=$NUMBER_PROCESSORS\n" | $SUDO tee -a /var/spool/torque/server_priv/nodes
    done

    # TODO: workaround for Debian bug #XXXXXX
    $SUDO /etc/init.d/torque-server stop
    sleep 6
    $SUDO /etc/init.d/torque-server start

    # TODO: workaround for Debian bug #XXXXXX, also catch return code with echo
    echo `$SUDO killall pbs_sched`
    sleep 2
    $SUDO /etc/init.d/torque-scheduler start

#   $SUDO /etc/init.d/torque-server restart
#   $SUDO /etc/init.d/torque-scheduler restart


    $SUDO qmgr -c "s s scheduling=true"
    $SUDO qmgr -c "c q batch queue_type=execution"
    $SUDO qmgr -c "s q batch started=true"
    $SUDO qmgr -c "s q batch enabled=true"
    $SUDO qmgr -c "s q batch resources_default.nodes=1"
    $SUDO qmgr -c "s q batch resources_default.walltime=3600"
    # had to set this for MPI, TODO: double check
    $SUDO qmgr -c "s q batch resources_min.nodes=1"
    $SUDO qmgr -c "s s default_queue=batch"
    # let all nodes submit jobs, not only the server
    $SUDO qmgr -c "s s allow_node_submit=true"
    #$SUDO qmgr -c "set server submit_hosts += $TORQUE_HEAD_NODE_IP"
    #$SUDO qmgr -c "set server submit_hosts += $INSTANCE_IP"

    # adding extra nodes
    #$SUDO qmgr -c "create node $INSTANCE_HOSTNAME"

    #debug
    cat /var/spool/torque/server_logs/$DATE
    qstat -q
    pbsnodes -a
    cat /etc/torque/server_name
fi


# END   execution in instance ###############################################
exit 0
