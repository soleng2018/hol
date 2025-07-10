# Hands-on-Lab and Demo Scripts
All scripts required to run an Hands-on-Lab or demos

# Setup the Server

## Install git and checkout the scripts
```
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/soleng2018/hol.git
```

## Make all files executable
```
cd hol
sudo chmod +x *
```

## Install docker
If you already have docker installed you can skip this step
```
./installdocker.sh
```
Select 1 as the option