# My homemade distributed kubernetes cluster

Here is how I configured my own multinode Kubernetes cluster running on my own hardware, in multiple zones.

Below you can see the setup I configured, of course you can change it by having more or less nodes, using different OSs,
node architectures, etc. The only constraint you should keep by following this guide, is to rely on microk8s to set up
the Kubernetes cluster.

Here are my node names, you may see them referenced in this guide:

1. Master: asus-r420ma
2. Worker 1: hp-840-g8
3. Worker 2: hp-zbook-g11

So my current setup is composed by 3 nodes: 1 master, 2 workers. As you may notice, there's no _High Availability_ so
far as it would require at least 3 master nodes. But as it's a personal, didactic cluster and I'm using some hardware I
own so it's quite fine this way. Note that each node can run over a linux or Windows machine. I'd anyway suggest to run
at least the master in a linux machine.

## Setting up all the nodes

### Linux nodes:

I started from a fresh installation of Ubuntu 24.04 LTS, but basically any distro would be fine.

First of all, install _microk8s_ on each node as described [here](https://microk8s.io/docs/getting-started):
> sudo snap install microk8s --classic

To avoid the need of root privileges any time you have to execute the microk8s command:
> sudo usermod -a -G microk8s $USER
> mkdir -p ~/.kube
> chmod 0700 ~/.kube
> su - $USER

In the master node only, also enable the following add-ons:

> microk8s enable dns
> microk8s enable ingress
> microk8s enable metrics-server
> microk8s enable hostpath-storage

:information_source: In case one or more nodes will be used to running Kubernetes cluster only, you may consider
installing Ubuntu server distribution or any similar one, it comes without a graphical interface and therefore requires
less resources that you can instead use to run your PODs.

### Windows nodes:

To configure my windows nodes, I followed the same steps described above on **WS2L** (Windows Subsystem For Linux
Version 2). If can find many online tutorials about how to enable WSL2 on your Windows machine.

### Network between the nodes

Worker and master nodes need to live within the same local network. So let's create a VPN to handle it.

#### Configuring the master nodes

##### Setting up the VPN

Let's start from the master by installing the openvpn server on it.

> sudo apt install openvpn easy-rsa

_easy-rsa_ will help us in preparing the CA and server and clients certificate:

> sudo make-cadir /etc/openvpn/easy-rsa

As root user:
> ./easyrsa init-pki
> ./easyrsa build-ca

Let's choose a name for your server (master node) and run the following commands:
> ./easyrsa gen-req myservername nopass
> ./easyrsa gen-dh
> ./easyrsa sign-req server myservername

All certificates and keys have been generated. Common practice is to copy them to _/etc/openvpn/_:
> cp pki/dh.pem pki/ca.crt pki/issued/myservername.crt pki/private/myservername.key /etc/openvpn/

Still from the master node, choose a name for your client and run the following commands:
> ./easyrsa gen-req myclient1 nopass
> ./easyrsa sign-req client client-hp-840-g8-windows

Do that for each client (worker node) and securely copy the following files into related worker machines:
> /etc/openvpn/ta.key \
> /etc/openvpn/easy-rsa/pki/ca.crt \
> /etc/openvpn/easy-rsa/pki/issued/myclient.crt \
> /etc/openvpn/easy-rsa/pki/private/myclient.key

Configure the server by copying the following configuration file template
> sudo cp /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz /etc/openvpn/myserver.conf.gz
> sudo gzip -d /etc/openvpn/myserver.conf.gz

:warning: Please note that - in my case, for soma reason - the sample file was empty and therefore I needed to copy it
from [here](https://github.com/OpenVPN/openvpn/blob/master/sample/sample-config-files/server.conf).

Update the following lines:
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

You can also check if VPN route exists:
> ip route
> [...]
> 10.8.0.0/24 dev tun0 proto kernel scope link src 10.8.0.1

Let's also add all the node's hostnames in each machines' _/etc/hosts_ file:
> 10.8.0.1 asus-r420ma master.k8s.local \
> 10.8.0.2 hp-840-g8 \
> 10.8.0.3 hp-zbook-g11

Openvpn troubleshooting and more info can be
found [here](https://documentation.ubuntu.com/server/how-to/security/install-openvpn/)

##### Setting up the SSH server (optional)

In case you also want to control the master node from a VPN client, let's quickly configure an SSH server on it.

Install the SSH server:
> sudo apt install openssh-server

Create the SSH keys:
> ssh-keygen -t rsa

Securely copy the _id_rsa.pub_ into  ~/.ssh in any client machine you want to connect against the master node. Then execute:
> ssh-copy-id username@remotehost

or in case of errors:
> ssh-copy-id -f -i id_rsa.pub username@remotehost

By now, you should be able to connect against the master node from the client by running:
> ssh username@remotehost

[//]: # (##### Setting up the SSH server)

[//]: # ()

[//]: # (As my master node has a limited amount of memory, I decided to remove the ubuntu GUI. To do that, I just)

[//]: # (followed [this guide]&#40;https://www.homelab-adventures.com/posts/removing-desktop-gui-from-ubuntu-server/&#41;.)

[//]: # (If you are going to install Ubuntu from scratch, you can just install Ubuntu server as it is natively without user)

[//]: # (graphical interface.)

#### Configuring the worker nodes

##### Ubuntu linux based machines

Let's install openvpn client in each worker node:
> sudo apt install openvpn

Copy the files generated in the master node as described above.

Configure the client by copying the following configuration file template
> sudo cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf /etc/openvpn/

and updating the following lines:
> client
> ca ca.crt \
> cert myclient1.crt \
> key myclient1.key \
> tls-auth ta.key 1

Also ensure the *client* keyword is in the config file, since that’s what enables client mode.
And add your master node address:

> remote vpnserver.example.com 1194

Of course, if - like me - your master node is in some home network, you need to find a way to let it be always reachable
at the same address. I am using a _dyn dns server_ to achieve that. Also don't forget to add the 1194 port to your home
router port mapping configuration.

Done!

You can now start your openvpn client in your worker(s) node(s):
> $ sudo systemctl start openvpn@myclient

And check the status:
> sudo journalctl -u openvpn@myclient -xe
>
> sudo systemctl status openvpn@client.service

Also check the VPN route exists:
> ip route
> [...]
> 10.8.0.0/24 dev tun0 proto kernel scope link src 10.8.0.2

##### Windows based machines

Here again, you can follow the same steps described in the linux sections against your _WSL2_ installation. But before,
you need to apply some configuration to WSL2 to let our VPN work smoothly:

1. Create a _.wslconfig_ file in your profile directory with the following content:

> [wsl2] \
> networkingMode=mirrored # Do not create an additional virtual LAN for WSL but use the host one
>
> [network] \
> generateHosts=false # avoid /etc/hosts file is recreated at startup \
> generateResolvConf=false

2. Run the following command in PowerShell window with admin privileges:

> Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow

The first step is needed to avoid that Windows creates an additional virtual LAN to be used by WSL, the second one
enables incoming connections against the WSL network. Without those additional configuration, the master node would not
be able to open connections against the windows worker and many feature would not work, for example you could not stream
logs in the master command line if the POD is running in the Windows worker.

3. Update hostname
   To change your machine name on WSL, without changing the PC name in Windows, just edit the _/etc/hostname_ file.

In case of issues with _hosts_ file and similar ones being recreated at startup by WSL, follow the instructions
in [this github comment](https://gist.github.com/coltenkrauter/608cfe02319ce60facd76373249b8ca6?permalink_comment_id=4468904).

4. If you additionally want to connect to the cluster form your Windows machine, for example from a browser, you will
   need to create a new VPN connection by installing the openvpn connect client for windows and set up a new client from
   the server as explained above.
   After the client is installed, securely copy the following files into _C:\Program Files\OpenVPN Connect_:
   > /etc/openvpn/ta.key \
   > /etc/openvpn/easy-rsa/pki/ca.crt \
   > /etc/openvpn/easy-rsa/pki/issued/myclient.crt \
   > /etc/openvpn/easy-rsa/pki/private/myclient.key

   And create a new configuration file for the client as explained in the linux section, the only difference is that the
   file extension should be _.ovpn_ instead of _.conf_ but the content should be exact the same. Lastly, just drag and
   drop this file into the vpn connect client, and you are done!
   Also don't forget to update the Windows hosts file with same content of the WSL one.

   :warning: In case you are using the same Windows machine for both running as cluster node and accessing to the
   cluster from you Windows browser and you followed all the step mentioned above, your machine will have 2 simultaneous
   VPN connections against the master node (1 from Windows connect client and another one form the WSL2 openvpn client).
   This means your client have a duplicated route against the openvpn server.
   But don't worry! Everything will actually work fine anyway, you only have to take care about one thing: the Windows
   openvpn connect client connection must be enabled only after the one from WSL2 was established. Otherwise, if you
   don't want to have such ugly duplicated route, you can disable the WSL2 vpn and keep only the one from the Windows
   client. This way it should work fine because - as stated above - we configured the WSL2 network to be a mirror of the
   Windows one.

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

and copy it in the machine you want to run kubectl against the cluster, in the _~/.kube/_ path.

#### kube-ps1

Very handy tools to quickly see in your cmd prompt the k8s current context and namespace.

Download the [following file](https://github.com/jonmosco/kube-ps1/blob/master/kube-ps1.sh) and copy it into the
previously created _bin_ folder. Add the following lines in your _bashrc_ file:
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
>
deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/
> all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
>
> sudo apt-get update
>
> sudo apt-get install helm

### Creating the cluster

Let's start microk8s in each node:
> microk8s start

#### Adding the workers

To let worker nodes joining the cluster, just trigger the following command from the master:
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

As our cluster is meant to rely on the VPN we created, we need to pick the command containing our VPN address:
> microk8s join 10.8.0.1:25000/f35f519831a8ba0df8b6b878408a0a90/abd47992aee6 --worker

:warning: Don't forget to add the _--worker_ arg when you'll execute it.

The command above must be executed on each _worker_ node. Please note that you will need to generate the command (token)
for each of them.

:information_source: If everything worked successfully, you should now able to see all your cluster nodes by running:
> kubectl get nodes

#### Labelling the nodes

After the cluster creation is completed, let's add the following label to the master:
> microk8s kubectl label node mymasternode node-role.kubernetes.io/master=master

and this one to each worker:
> microk8s kubectl label node myworkernode node-role.kubernetes.io/worker=worker

Assigned roles are visible by executing:
> microk8s kubectl get nodes

Optionally, you can state the cluster topology. In my case, the nodes are spread between Italy and Switzerland.
So according to their location I will add the following labels:

> microk8s kubectl label node mynode topology.kubernetes.io/zone=eu-it-mi
>
> microk8s kubectl label node mynode topology.kubernetes.io/region=eu-it

and:

> microk8s kubectl label node mynode topology.kubernetes.io/zone=eu-ch-ti
>
> microk8s kubectl label node mynode topology.kubernetes.io/region=eu-ch
