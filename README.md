# FRIGATE -- TELEGRAM -- NAS

This repo is created for the following requirements 
- One-click installation of Frigate NVR
- Enable automatic saving of review clips to local folder (optionally to NAS)
- Notify the saved review clip through Telegram Bot service

(Note: Review -> compilation of simultaneous events; as of Frigate 0.17, the API doesn't allow for a compiled clip for each review item but individual event clips can be called)

# Pre-requisites for Installation

Following are the prerequisites for this installation
- Working Linux distro on a machine with network connectivity
- Accessible MQTT Broker with valid username and password. (In case there is no external MQTT broker setup, applications like Eclipse, EMQX, etc. can be installed on the same machine)

If the setup is being deployed in a Proxmox container along with an edge device like Coral TPU, USB-Pass through is essential which can be enabled by the following commands

Enter the following command in Proxmox Node Shell
```bash
cd /etc/pve/lxc 
```
Locate the .conf file related to the container (e.g: 100.conf) and run the following command
```bash
nano 100.conf
```
Add the following lines at the end of the file to allow USB-Pass through
```bash
lxc.mount.entry: /dev/bus/usb/001/ dev/bus/usb/001/ none bind,optional,create=dir 0,0
lxc.mount.entry: /dev/bus/usb/002/ dev/bus/usb/002/ none bind,optional,create=dir 0,0
lxc.mount.entry: /dev/bus/usb/003/ dev/bus/usb/003/ none bind,optional,create=dir 0,0 
```

# Frigate NVR Installation

SSH into the machine and run the following command
```bash
wget -O frigate.sh https://raw.githubusercontent.com/the-real-techfreak/frigate-telegram-nas/main/install_frigate.sh && chmod +x frigate.sh && sudo ./frigate.sh
```
The above script completes the following actions
- Install Docker, Docker-Compose and corresponding dependencies
- Create **directories** for frigate container (\main\frigate\{config,data}
- Create a sample **configuration** for frigate (\main\frigate\config\config.yml)
- Create a **.env** file for user input related to MQTT (\main\.env)
- Create a **compose.yml** (\main\compose.yml) for docker-compose to run the following containers -> dozzle (monitoring logs), frigate

If the requirement is only Frigate installation, please proceed to below steps after the script finishes, to complete the setup:
- provide MQTT details in the .env file using the following command
```bash
sudo nano \main\.env
```
- Update the frigate config file with your camera details using the following command
```bash
sudo nano \main\frigate\config\config.yml
```

If you need to save the review clips and forward them using Telegram Bot, please proceed to the next step 
