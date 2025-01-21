# My homemade distributed kubernetes cluster

## Setting up all the nodes

Here is the setup I configured.
Of course, you can change it by having more or less nodes, using different OSs or node architectures, etc.
The only constraint by following this guide is to rely on microk8s to set up the Kubernetes cluster.

Here are my nodes:

1. Master: asus-r420ma
2. Worker 1: hp-840-g8
3. Worker 2: hp-zbook-g11-it-r

Setup: 3 nodes: 1 master, 2 workers (no HA so far)
Each node can run over a linux or windows machine.

About linux nodes:
I started from a fresh installation of Ubuntu 24.04 LTS.
Installed microk8s as described [here](https://microk8s.io/docs/getting-started):

> sudo snap install microk8s --classic


Also, don't forget to enable the add-ons:

> microk8s enable dns
> microk8s enable ingress
> microk8s enable metrics-server
> microk8s enable hostpath-storage


About the windows nodes:
TODO...

### Network between the nodes

Worker and master nodes need to live within the same local network. So let's create a VPN to handle it.

#### Configuring the master nodes

##### Setting up the VPN

After identifying which of your nodes will be the master, let's install the openvpn server on it.

> sudo apt install openvpn easy-rsa

easy-rsa will help us in preparing the CA and server and clients certificate:

> sudo make-cadir /etc/openvpn/easy-rsa

As root user:
> ./easyrsa init-pki
> ./easyrsa build-ca

Let's choose a name for your server and run the following commands:
> ./easyrsa gen-req myservername nopass
> ./easyrsa gen-dh
> ./easyrsa sign-req server myservername

All certificates and keys have been generated. Common practice is to copy them to _/etc/openvpn/_:
> cp pki/dh.pem pki/ca.crt pki/issued/myservername.crt pki/private/myservername.key /etc/openvpn/

Still from the master node, choose a name for your client and run the following commands:
> ./easyrsa gen-req myclient1 nopass
> ./easyrsa sign-req client myclient1

Do that for each client (worker node) and securely copy the following files into related worker machines:
> /etc/openvpn/easy-rsa/pki/ca.crt
> /etc/openvpn/easy-rsa/pki/reqs/myclient.req
> /etc/openvpn/easy-rsa/pki/issued/myclient.crt

Configure the server by copying the following configuration file template
> sudo cp /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz /etc/openvpn/myserver.conf.gz
> sudo gzip -d /etc/openvpn/myserver.conf.gz

Please note that - in my case, for soma reason - the sample file was empty and therefore I needed to copy it
from [here](https://github.com/OpenVPN/openvpn/blob/master/sample/sample-config-files/server.conf)
and later changing few values as described in the tutorial page linked above.

and updating the following lines:
> dh dh.pem
> ca ca.crt
> tls-auth ta.key 0
> key myservername.key
> cert myservername.crt

Edit _/etc/sysctl.conf_ and uncomment the following line to enable IP forwarding:
> #net.ipv4.ip_forward=1

And run:
> sudo sysctl -p /etc/sysctl.conf

Done!

You can now start your openvpn server in your master node:
> sudo systemctl start openvpn@server.service

and check it is up and running:
> sudo systemctl status openvpn@server.service

Logs can be found here:
> > sudo journalctl -u openvpn@myserver -xe

You can also check the if VPN route exists:
> ip route
> [...]
> 10.8.0.0/24 dev tun0 proto kernel scope link src 10.8.0.1


Openvpn troubleshooting and more info can be
found [here](https://documentation.ubuntu.com/server/how-to/security/install-openvpn/)

##### Setting up the SSH server (optional)

I want to control the master node (also) from a VPN client. So let's briefly see how to configure it.

Install the VPN server:
> sudo apt install openssh-server

Create the SSH keys:
> ssh-keygen -t rsa

Securely copy the _id_rsa.pub_ in the client machine and add it by running:
> ssh-copy-id username@remotehost

By now, you should be able to connect against the master node from the client by running:
> ssh username@remotehost

##### Setting up the SSH server

As my master node as a limited amount of memory, I decided to remove the ubuntu GUI. To do that, I just
followed [this guide](https://www.homelab-adventures.com/posts/removing-desktop-gui-from-ubuntu-server/).
If you are going to install Ubuntu from scratch, you can just install Ubuntu server as it is natively without user
graphical interface.

#### Configuring the worker nodes

##### Ubuntu linux based machines

Let's install openvpn client in each worker node:
> sudo apt install openvpn

Copy the files generated in the master node as described above.

Configure the client by copying the following configuration file tremplate
> sudo cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf /etc/openvpn/

and updating the following lines:
> ca ca.crt
> cert myclient1.crt
> key myclient1.key
> tls-auth ta.key 1

Also ensure the *client* keyword is in the config file, since that’s what enables client mode and add your master node
address:

> client
> remote vpnserver.example.com 1194

Of course, if - like me - your master node is in some home network, you need to find a way to let it be always reachable
at the same address. I am using a syn dns server to achieve that. Also don't forget to add the 1194 port to your home
router port mapping configuration.

Done!

You can now start your openvpn client in your worker(s) node(s):
> $ sudo systemctl start openvpn@myclient

And check the status:
> sudo journalctl -u openvpn@myclient -xe


Don't forget to uncomment this line in the openvpn client conf file:
> tls-auth ta.key 1


Start the VPN client in each worker node:
> sudo systemctl start openvpn@client.service

and check it is up and running:
> sudo systemctl status openvpn@client.service

Also check the VPN route exists:
> ip route
> [...]
> 10.8.0.0/24 dev tun0 proto kernel scope link src 10.8.0.2

##### Windows based machines

To configure my windows nodes, I followed the same steps and installed the same tools described above on **WSL** (
Windows Subsystem For Linux Version 2).
Before, after enabling WSL 2 on your windows machine, you need to additional steps:

1. Create a _.wslconfig_ file in your profile directory with the following content:

> [wsl2]
> networkingMode=mirrored

2. Run the following command in PowerShell window with admin privileges:

> Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow

The first step is needed to avoid that Windows creates an additional virtual LAN to be used by WSL, the second one
enables incoming connections against the WSL network. Without those additional configuration, the master node would not
be able to open connections against the windows worker and many feature would not work, for example you could not stream
logs in the master command line if the POD is running in the Windows worker.

### Tools

Here are the minimum required tools to be installed in the master and optionally worker nodes:

#### Curl

> sudo apt install curl

#### Kubectl

I created a _bin_ directory in my user folder where I'm adding all the binaries:
> cd ~
>
> mkdir bin
>
> curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
>
> chmod +x kubectl

Don't forget to add such folder to your _$PATH_.

##### Operating from worker nodes

In order to use your kubectl from a worker node or any other machine connected against the same VPN you can easily
create - from the master node - the kube config file:
> microk8s config > config

and copy if in the machine you want to run kubectl against the cluster, in the _~/.kube/_ path.

#### kube-ps1

Very handy tools to quickly see in your cmd prompt the k8s current context and namespace.

Download the [following file](https://github.com/jonmosco/kube-ps1/blob/master/kube-ps1.sh) and copy it into the
previously created _bin_ folder.
Add the following lines in your _bashrc_ file:
> source ~/bin/kube-ps1.sh
>
> PS1='[\u@\h \W $(kube_ps1)]\$ '

For further customization you can have a look [here](https://github.com/jonmosco/kube-ps1/blob/master/kube-ps1.sh).

#### Helm 3

> curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
>
> sudo apt-get install apt-transport-https --yes
>
> echo "
>
deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/
> all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
>
> sudo apt-get update
>
> sudo apt-get install helm

### Creating the cluster

Let's install microk8s on each node.
All my nodes are base on Ubuntu or WSL2 over Windows 11.
The installation process is basically the same and trivial:
> sudo snap install microk8s --classic

To avoid the need of root privileges any time you have to execute the microk8s command:
> sudo usermod -a -G microk8s $USER
> mkdir -p ~/.kube
> chmod 0700 ~/.kube
> su - $USER

That's it!

Let's now start microk8s:
> microk8s start

#### Preparing the master node

In the master node, you need to additionally enable few microk8s add-ons:
> microk8s enable dns
> microk8s enable hostpath-storage
> ...

#### Adding the workers

To let worker nodes joining the cluster, just trigger the following command on the master:
> microk8s add-node
>
> From the node you wish to join to this cluster, run the following:
> microk8s join 192.168.1.11:25000/f35f519831a8ba0df8b6b878408a0a90/abd47992aee6
>
> Use the '--worker' flag to join a node as a worker not running the control plane, eg:
> microk8s join 192.168.1.11:25000/f35f519831a8ba0df8b6b878408a0a90/abd47992aee6 --worker
>
> If the node you are adding is not reachable through the default interface you can use one of the following:
> microk8s join 192.168.1.11:25000/f35f519831a8ba0df8b6b878408a0a90/abd47992aee6
> microk8s join 10.8.0.1:25000/f35f519831a8ba0df8b6b878408a0a90/abd47992aee6

Note that our cluster is meant to rely on the VPN we created, so we need to pick the command containing our VPN address.
Also don't forget to add the _--worker_ arg:
> microk8s join 10.8.0.1:25000/f35f519831a8ba0df8b6b878408a0a90/abd47992aee6 --worker

The command above must be executed on each _worker_ node. Please note that you will need to generate the command (token)
for each of them.

#### Labelling the nodes

After the cluster creation is completed, let's add the following label to the master:
> microk8s kubectl label node myworkernode node-role.kubernetes.io/master=master

and this one to each worker:
> microk8s kubectl label node myworkernode node-role.kubernetes.io/worker=worker

Assigned roles are visible by executing:
> microk8s kubectl get nodes

I also want to state the topology of my cluster. My nodes will be actually spread between Italy and Switzerland. So
according to their location I will add the following labels:

> microk8s kubectl label node mynode topology.kubernetes.io/zone=eu-it-mi
>
> microk8s kubectl label node mynode topology.kubernetes.io/region=eu-it

and:

> microk8s kubectl label node mynode topology.kubernetes.io/zone=eu-ch-ti
>
> microk8s kubectl label node mynode topology.kubernetes.io/region=eu-ch
