# Copyright 2010-2011 Dominique Belhachemi
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

import os
import multiprocessing
from socket import gethostbyaddr 
from fabric.api import run, sudo, settings, env, local
from fabric.contrib import files
import subprocess
import fabric
import urllib2
import time

# cc = cloud cluster
env.cc_interface='private'
env.cc_debug=1

# can only be startet on some special instances
def init_nfs_server():
    init_instance()
    install_package('nfs-kernel-server')
    if files.exists('/data', use_sudo=False, verbose=True):
        print('/data already exists')
    else:
        sudo('mkdir -p /data')
        sudo('mkdir -p /data/test')
        sudo('chmod -R 777 /data')

    sudo('rm -f /etc/exports')
    sudo('touch /etc/exports')

    sudo('exportfs -ar')


def add_worker_to_nfs(worker_ip):
    text="/data "+worker_ip+"(rw,sync,no_subtree_check)\n"
    files.append(text, '/etc/exports', use_sudo=True)
    sudo('exportfs -ar')


def add_worker_to_head(worker_ip, np):

    if env.cc_interface == 'private':
        worker_hostname = get_private_hostname_from_ip(worker_ip)

    if not files.contains(worker_hostname, '/etc/hosts'):
        files.append(worker_ip+' '+worker_hostname, '/etc/hosts', use_sudo=True)

    # changes /var/spool/torque/server_priv/nodes
    sudo('qmgr -c "create node '+worker_hostname+' np='+np+'"')


def remove_worker_from_head(worker_ip, np):

    if env.cc_interface == 'private':
        worker_hostname = get_private_hostname_from_ip(worker_ip)

    # changes /var/spool/torque/server_priv/nodes
    sudo('qmgr -c "delete node '+worker_hostname+' np='+np+'"')


def add_head_to_worker(head_ip):
    head_hostname = get_hostname_from_ip(head_ip)
    if not files.contains(head_hostname, '/etc/hosts'):
        files.append(head_ip+' '+head_hostname, '/etc/hosts', use_sudo=True)

    sudo('rm -f /etc/torque/server_name')
    files.append(head_hostname, '/etc/torque/server_name', use_sudo=True)


def init_worker_node(head_ip, nfs_ip):
    init_instance()

    install_package('torque-mom torque-client')

    # install portmap for NFS
    install_package('portmap')
    install_package('nfs-common')

    if not files.contains(nfs_ip, '/etc/fstab'):
        files.append(nfs_ip+':/data  /mnt/data  nfs  defaults  0  0\n', '/etc/fstab', use_sudo=True)

    sudo('mkdir -p /mnt/data')
#    sudo('umount /mnt/data -v')
#    sudo('mount /mnt/data -v')

    # install OpenMPI packages
    #if [ $MPI == 1 ] ; then
    #    install_package "linux-headers-2.6.35-22-virtual"
    #fi

    MPI=0
    # install OpenMPI packages
    if MPI == 1:
        install_package("libopenmpi-dev")
        install_package("openmpi-bin")

        #compile MPI test program
        run('bash compileMPI.sh')

    # might not be necessary anymore because of mpi tm support
    if MPI == 1:
        sudo('mkdir -p /etc/torque')
#        $SUDO rm -f /etc/torque/hostfile
#        $SUDO touch /etc/torque/hostfile
#        for TORQUE_WORKER_NODE_HOSTNAME in `echo $TORQUE_WORKER_NODES_HOSTNAME`
#            if ! egrep -q "$TORQUE_WORKER_NODE_HOSTNAME" /etc/torque/hostfile ; then
#                # todo: numer_procs?
#                echo "$TORQUE_WORKER_NODE_HOSTNAME slots=1" | $SUDO tee -a /etc/torque/hostfile


    if env.cc_interface == 'private':
        hn = get_private_hostname_from_ip(head_ip)
        add_head_to_worker(get_private_ip_from_hostname(hn))
    if env.cc_interface == 'public':
        add_head_to_worker(head_ip)


    # kill running process
    sudo('echo `killall -s KILL pbs_mom`')

    # get rid of old logs
    sudo('rm -f /var/spool/torque/mom_logs/*')

    # create new configuration
    sudo('rm -f /var/spool/torque/mom_priv/config')
    files.append('$timeout 120', '/var/spool/torque/mom_priv/config', use_sudo=True)
    files.append('$loglevel 5', '/var/spool/torque/mom_priv/config', use_sudo=True)


    # try to start torque-mom (pbs_mom) up to 3 times
    for i in range(3):
#        if [ -z "$(pgrep pbs_mom)" ] ; then
        if 1:
            # pbs_mom is not running
            sudo('/etc/init.d/torque-mom start')
#            sleep 1
        else:
            # pbs_mom is running
            break


    # debug
    from datetime import date
    for value in run("date '+%Y%m%d'").splitlines():
        print(value)
        DATE = value
    #DATE=date.today().strftime("%Y%m%d")
    sudo('touch /var/spool/torque/mom_logs/'+DATE)
    sudo('cat /var/spool/torque/mom_logs/'+DATE)


def init_head_node():
    init_instance()
    install_package('torque-server torque-scheduler torque-client')

    # for debugging
    install_package('sendmail mutt')


    if env.cc_interface == 'public':
        instance_hostname = get_public_instance_hostname()
        instance_ip = get_public_instance_ip()

        #this one is for the scheduler, if using the public interface
        if not files.contains(instance_hostname, '/etc/hosts') and not files.contains('127.0.1.1', '/etc/hosts'):
            files.append('127.0.1.1 '+instance_hostname, '/etc/hosts', use_sudo=True)

    elif env.cc_interface == 'private':
        instance_hostname = get_public_instance_hostname()
        instance_ip = get_private_instance_ip()
    else:
        # TODO error
        return -1

    sudo('rm -f /etc/torque/server_name')
    files.append(instance_hostname, '/etc/torque/server_name', use_sudo=True)

    # TODO: workaround for Debian bug #XXXXXX
    sudo('/etc/init.d/torque-server stop')
    time.sleep(6)
    sudo('/etc/init.d/torque-server start')

    # TODO: workaround for Debian bug #XXXXXX, also catch return code with echo
    sudo ('echo `killall pbs_sched`')
    time.sleep(2)
    sudo('/etc/init.d/torque-scheduler start')

#   $SUDO /etc/init.d/torque-server restart
#   $SUDO /etc/init.d/torque-scheduler restart

    sudo('qmgr -c "s s scheduling=true"')
    sudo('qmgr -c "c q batch queue_type=execution"')
    sudo('qmgr -c "s q batch started=true"')
    sudo('qmgr -c "s q batch enabled=true"')
    sudo('qmgr -c "s q batch resources_default.nodes=1"')
    sudo('qmgr -c "s q batch resources_default.walltime=3600"')
    # had to set this for MPI, TODO: double check
    sudo('qmgr -c "s q batch resources_min.nodes=1"')
    sudo('qmgr -c "s s default_queue=batch"')
    # let all nodes submit jobs, not only the server
    sudo('qmgr -c "s s allow_node_submit=true"')
    #$SUDO qmgr -c "set server submit_hosts += $TORQUE_HEAD_NODE_IP"
    #$SUDO qmgr -c "set server submit_hosts += $INSTANCE_IP"

#subprocess.call(["sudo", "aptitude", "update"])
def update():
    host_type()
    with settings(warn_only=True):
        sudo('aptitude update', pty=True)


def install_package(package):
    with settings(warn_only=True):
        sudo('apt-get -o Dpkg::Options::="--force-confnew" --force-yes -y install %s' % package, pty=True)


def init_instance():
    run('hostname')

    print(env.cc_interface)

    os.environ["DEBIAN_FRONTEND"] = "noninteractive"
    os.environ["APT_LISTCHANGES_FRONTEND"] = "none"

    # those variables are needed for the locales package
    os.environ["LANGUAGE"] = "en_US.UTF-8"
    os.environ["LANG"] = "en_US.UTF-8"
    os.environ["LC_ALL"] = "en_US.UTF-8"

    # for dialog frontend
    os.environ["PATH"] = "$PATH:/sbin:/usr/sbin:/usr/local/sbin"
    os.environ["TERM"] = "linux"

    # clean-up
    sudo('dpkg --configure -a')

    # apt update package source information
    update()

    install_package("curl")

    install_package('lsb-release')

    # get some information about the Operating System,
    # it might fail with"No LSB modules are available."
    for value in run('lsb_release -i -s').splitlines():
        print(value)
        DISTRIBUTOR = value
    for value in run('lsb_release -c -s').splitlines():
        print(value)
        CODENAME = value
 
    # for torque on Ubuntu
    if DISTRIBUTOR == "Ubuntu":
        text  = 'deb http://us-east-1.ec2.archive.ubuntu.com/ubuntu/ '+CODENAME+' multiverse'
        files.append(text, '/etc/apt/sources.list', use_sudo=True)


    # for torque on Debian lenny
    if DISTRIBUTOR == "Debian" and CODENAME == "lenny":
        if not files.contains('lenny-backports', '/etc/apt/sources.list'):
            text = 'deb http://backports.debian.org/debian-backports lenny-backports main'
            files.append(text, '/etc/apt/sources.list', use_sudo=True)

    #echo "deb http://ftp.us.debian.org/debian sid main" > /etc/apt/sources.list
    #echo "deb http://ftp.us.debian.org/debian squeeze main" > /etc/apt/sources.list
    #echo "deb http://security.debian.org/ squeeze/updates main" >> /etc/apt/sources.list


    # get rid of some error messages because of missing locales package
    install_package('locales')
    sudo('rm -f /etc/locale.gen')
    files.append('en_US.UTF-8 UTF-8', '/etc/locale.gen', use_sudo=True)
    sudo('locale-gen')



    if env.cc_debug:
        # install nmap
        install_package('nmap')
        run('nmap localhost -p 1-20000')

    # install ntpdate
    install_package('ntpdate')
    ###$SUDO ntpdate pool.ntp.org
    sudo('ntpdate ntp.ubuntu.com')



def host_type():
    run('uname -s')


def uname_machine():
    run('uname -m')


def get_private_ip_from_hostname(hostname):
        for value in run('nslookup '+str(hostname)+' | grep Address | grep -v \'#\' | cut -f 2 -d \' \'').splitlines():
            print(value)
            return value


def get_private_hostname_from_ip(ip):
    hostname = get_hostname_from_ip(ip)
    pr_ip = get_private_ip_from_hostname(hostname)
    return get_hostname_from_ip(pr_ip)

def get_private_instance_ip():
    for value in run('/sbin/ifconfig eth0 | grep \"inet addr\" | awk \'{print $2}\' | sed \'s/addr\://\'').splitlines():
        print(value)
        return value


def get_private_instance_hostname():
    return 'todo'
    #todo    return "sdfsdfss" nslookup privateip?

def get_public_instance_ip():

    for value in run('/usr/bin/curl -s http://169.254.169.254/latest/meta-data/public-ipv4').splitlines():
        print(value)
        return value

def get_public_instance_hostname():
    
    # get instance information
    os.environ["METADATA_URL "] = "http://169.254.169.254/latest/meta-data/"

    for value in run('/usr/bin/curl -s http://169.254.169.254/latest/meta-data/public-hostname').splitlines():
        print(value)
        return value

#    INSTANCE_PUBLIC_IP = os.popen('/usr/bin/curl -s $METADATA_URL/public-ipv4').read()

#    com = '/usr/bin/curl -s http://169.254.169.254/latest/meta-data/public-ipv4'
#    INSTANCE_PUBLIC_IP = subprocess.Popen(com, stdout=subprocess.PIPE, shell=True).communicate()[0]

#    INSTANCE_PUBLIC_IP = os.popen('/usr/bin/wget -qO- http://169.254.169.254/latest/meta-data/public-ipv4').read()

    #run('/usr/bin/wget -qO- http://169.254.169.254/latest/meta-data/public-ipv4 > /tmp/sfs.txts')

    #url='http://169.254.169.254/latest/meta-data/public-ipv4'
    #value = urllib2.urlopen(url).read()
    #print(value)


def get_hostname_from_ip(IP):
    for value in run('/usr/bin/nslookup '+str(IP)+' | grep "name =" | awk \'{print $4}\'').splitlines():
        # remove the trailing . from HOSTNAME (I get this from nslookup)
        print(value[:-1])
        return value[:-1]

    #todo: buggy, gets executed on my own computer
    #print(gethostbyaddr(ip)[0])
    #return gethostbyaddr(ip)[0]


#def get_ip_from_hostname(hostname):
#    print(gethostbyaddr(hostname)[2][0])
#    return gethostbyaddr(hostname)[2][0]


def get_number_procs():
    INSTANCE_NUMBER_PROCESSORS = multiprocessing.cpu_count()
    print(str(INSTANCE_NUMBER_PROCESSORS))

def replace_dots(IP):
   return "ip-" + IP.replace(".","-")

" " "
example session:

ec2-run-instances -t t1.micro $AMI -n1 -k gsg-keypair
ec2-describe-instances

user=ubuntu
nfsnode=184.72.151.50
headnode=184.72.151.50
keypath=../id_rsa-gsg-keypair
#fab -i ${keypath} -H ${user}@${headnode} init_nfs_server <- doesn't work well
fab -i ${keypath} -H ${user}@${headnode} init_head_node

Use the same node as a worker node instance

workernode=184.72.151.50
worker_np=1
fab -i ${keypath} -H ${user}@${workernode} init_worker_node:${headnode},${nfsnode}
fab -i ${keypath} -H ${user}@${headnode} add_worker_to_head:${workernode},${worker_np}

Start worker node instance and find out the hostname

ec2-run-instances -t t1.micro $AMI -n1 -k gsg-keypair
ec2-describe-instances

workernode=50.17.107.173
worker_np=1
fab -i ${keypath} -H ${user}@${workernode} init_worker_node:${headnode},${nfsnode}
fab -i ${keypath} -H ${user}@${headnode} add_worker_to_head:${workernode},${worker_np}

" " "
