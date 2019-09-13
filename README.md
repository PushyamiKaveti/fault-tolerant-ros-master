#Installation Instructions

Guidelines for building , testing and implementing ROS Rescue in custom ROS applications.Ros Rescue is included as an additional functionality inside rosmaster package for light-weight implementation. We have implemented the rescue feature in the source code of ROS which is available on this repository.

##System setup

We need to prepare the system to execute  roscore with rescue feature enabled , as a first step we make sure to have the prerequisites. Open the terminal and execute the following commands which take cares of python dependencies, initialize the ros dependencies and update the ros dependency packages.

```bash
$ sudo apt-get install python-rosdep python-rosinstall-generator python-wstool python-rosinstall build-essential
$ sudo rosdep init
$ rosdep update
```

To use ROS Rescue the code needs to be built from source. Open terminal and navigate to the folder of your choice  and clone the git repository mentioned above 

```bash
$ git clone https://github.com/PushyamiKaveti/fault-tolerant-ros-master.git
```


Now,  issue the following commands in the terminal. This will build the code locally in the current folder and help run the ros with fault tolerant feature. 
```bash
$ cd fault-tolerant-ros-master
$ ./src/catkin/bin/catkin_make_isolated --install -DCMAKE_BUILD_TYPE=Release 
```


Open the ros_env_setup.sh file present in the fault-tolerant-ros-master folder in a text editor. Find and replace all <your_path_folder> with the your local path. For example, if you have cloned our repository in home folder then the <your_path_folder> will be replaced as “~/fault-tolerant-ros-master”/ the absolute path of the file location. 
Also, the environment setup file has the list of environment variables which required for the run; sourcing the file will  keep the current shell aware of the environment variables. If you want to utilize the ros via other users in the system, kindly place the copy of the file in “/etc/profile.d/ros_env_setup.sh”  [ assuming you are running the ros in linux/unix platforms] which will load the file globally for all users in the system during login/shell spawning. 

```bash
$ source ros_env_setup.sh
```
##Running ROS Rescue

Once the environment is setup as per above section, now it’s time to run the roscore with rescue feature. ROS master with our rescue option will function and operate in the same fashion with additional capabilities of the logging and rescue. Only change is to initiate the roscore with “--rescue” option as seen below.

```bash
$ roscore --rescue
```
By default logs are saved in “ ~/.ros/log/latest-chkpt.yaml” with the system default’s umask value which enables everyone to read the logs. To keep the logs locked or to avoid manual intervention you can set the file permission to “655” [owner can read and write, other can only read and execute] by “chmod 655 ~/.ros/log/latest-chkpt.yaml”. This will help us keep the master state secure and stable.


If the ros master is running with fault tolerance enabled you should see “Ros Rescue enabled. Master is now fault tolerant!!!” printed to the console where roscore --rescue was executed as shown in the figure below. Another check that can be done is to make sure the master state is being saved to latest-ckhpt.yaml file mentioned above.

<img src="docs/images/output.png" alt="fault-tolerant master output" width="640" align="middle">



Ros rescue package also comes with a process to detect master failure called master-discovery.  Master monitor is required for failure detection and master restart. This executable can be run by issuing following commands. 

```bash
$  cd src/ros_comm/rosmaster/scripts/

$ ./master_monitor --rescue
```


To make sure ROS is working correctly  we can run a simple publisher/subscribe test as shown below.

```bash
$ cd  src/node_test/scripts/
$ python  talker.py
$ python listener.py
```

#DEMO VIDEOS

ROS with NO RESCUE : https://drive.google.com/drive/u/0/folders/11pLmd_hokq_K0R9v2zF1Asrwg2D4Yxen
ROS with Fault-tolerance : https://drive.google.com/drive/u/0/folders/11pLmd_hokq_K0R9v2zF1Asrwg2D4Yxen



