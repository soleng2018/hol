# Hands-on-Lab and Demo Scripts
All scripts required to run an Hands-on-Lab or demos

## Setup the Server
In this section we will prep our server to host the labs and or demos
### Prerequisites
* Fresh install of a Ubuntu based system
* WiFi or Wired Internet Connection
* A NSB ( Atleast One Switch and One AP )

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