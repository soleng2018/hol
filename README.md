# Hands-on-Lab and Demo Scripts
All scripts required to run hands-on labs or demos

## Setup the Server
In this section we will prep our server to host the labs and/or demos
### Prerequisites
* Fresh install of an Ubuntu-based system
* WiFi or Wired Internet Connection
* A NSB (At least One Switch and One AP)
* Server should have at least 2 ports if using WiFi as WAN, else 3 ports are needed

### Install git and openssh-server and checkout the scripts
```
sudo apt-get update
sudo apt-get install -y git openssh-server
git clone https://github.com/soleng2018/hol.git
```

### Make all files executable
```
cd hol
sudo chmod +x *
```

### Install docker
If you already have docker installed you can skip this step
```
./installdocker.sh
```
Select 1 as the option

### Verify Docker is installed and running
```
docker run hello-world
```

Following is the expected output
```
Hello from Docker!
This message shows that your installation appears to be working correctly.

To generate this message, Docker took the following steps:
 1. The Docker client contacted the Docker daemon.
 2. The Docker daemon pulled the "hello-world" image from the Docker Hub.
    (amd64)
 3. The Docker daemon created a new container from that image which runs the
    executable that produces the output you are currently reading.
 4. The Docker daemon streamed that output to the Docker client, which sent it
    to your terminal.

To try something more ambitious, you can run an Ubuntu container with:
 $ docker run -it ubuntu bash

Share images, automate workflows, and more with a free Docker ID:
 https://hub.docker.com/

For more examples and ideas, visit:
 https://docs.docker.com/get-started/
```

## Setup the hol
```
./setup.sh
```
### For Demos select the following
* access
* Select the interface to which the NSB will be connected e.g. enp1s0
* Number of pods - 1
* LAN IP - IP address of the NSB's default gateway
* LAN Subnet - The subnet including the mask for the NSB Uplink

### For training select the following
* trunk
* Select the interface to which the NSB will be connected e.g. enp1s0
* Number of pods - 10
* LAN IP - IP address of the NSB's default gateway
* LAN Subnet - The subnet including the mask for the NSB Uplink
Note: A Layer 2 switch will be needed. A trunk port from that switch will connect to the server. On the switch access vlans will need to be created for every NSB up links

## Install Windows docker image
There is an open-source project that makes it very simple to install Windows and macOS. You will need a Windows License to activate Windows after a trial period ends. Please ensure to get one.

### Check if your CPU supports virtualization
```
sudo apt install cpu-checker
sudo kvm-ok
```
If you receive an error from kvm-ok indicating that KVM cannot be used, please check whether the virtualization extensions (Intel VT-x or AMD SVM) are enabled in your BIOS.

### Create a MACVLAN docker network
In order to connect our Windows/macOS containers directly to the physical network, we need to use the macvlan network driver to assign a MAC address to each container's interface.

```
docker network create -d macvlan \
    --subnet=192.168.0.0/24 \
    --gateway=192.168.0.1 \
    --ip-range=192.168.0.96/28 \
    -o parent=eno1 pc_net
```
* The pc_net is the network name. Update the docker-compose.yml file if you choose to use a different name
* eno1 is the physical interface name. Replace it with your server's interface name (could be eth0 or enp1s0)

If we are using static IP address in the container, then pick one IP address from the network defined. If using DHCP, then this subnet is not used. But you will need to define it in order to create pc_net.

#### Verify the pc_net of type macvlan is created
```
docker network ls
```
The output should contain the following entry apart from other networks
```
NETWORK ID     NAME      DRIVER    SCOPE
..<snip>..
abe2c167ba0a   pc_net    macvlan   local
..<snip>..
```

### Bring up the Windows container
If passing a WiFi USB device, you will need to first get the vendorid and productid.
Execute the following command and identify your device
```
lsusb
```
In this example we are looking for
```
Bus 001 Device 010: ID 2357:012d TP-Link Archer T3U [Realtek RTL8812BU]
```
productid = 2357
vendorid = 012d

Update the line in docker-compose.yml
```
cd windows
nano docker-compose.yml
ARGUMENTS: "-device usb-host,vendorid=0x2357,productid=0x012d"
```
Hit Ctrl+X and Enter to save

#### Run docker compose
```
docker compose up -d
```
### Attach the default docker bridge
In order to use the web browser to manage the Windows machine, attach the default docker network
```
docker network connect bridge windows
```
"**bridge**" is the name of the default docker network and "**windows**" is the name of the container

* If you are on your host navigate to http://localhost:8006
* If you are SSH'ed in to your server navigate to http://your-server-IP:8006

## Install Linux docker image
```
cd linux
docker compose up -d
docker network connect bridge ubuntu
```
"ubuntu" is the name of the container. Replace it if you used a different name