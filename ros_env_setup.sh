#!/bin/bash
export TURTLEBOT_3D_SENSOR=kinect
export TURTLEBOT3_MODEL=burger
export ROS_ROOT=/home/pushyamik/ros_catkin_ws/install_isolated/share/ros
export ROS_PACKAGE_PATH=/home/pushyamik/ros_catkin_ws/src/ros_comm/rosbag:/home/pushyamik/ros_catkin_ws/install_isolated/share

export ROS_MASTER_URI=http://pushyamik-u:11311/ #replace with your hostname

export ROS_VERSION=1


export LD_LIBRARY_PATH=/home/pushyamik/ros_catkin_ws/devel_isolated/rosbag/lib:/home/pushyamik/ros_catkin_ws/install_isolated/lib:$LD_LIBRARY_PATH

export PATH=/home/pushyamik/ros_catkin_ws/devel_isolated/rosbag/bin:/home/pushyamik/ros_catkin_ws/install_isolated/bin:$PATH


export ROSLISP_PACKAGE_DIRECTORIES=/home/pushyamik/ros_catkin_ws/devel_isolated/rosbag/share/common-lisp

export ROS_DISTRO=kinetic

export PYTHONPATH=/home/pushyamik/ros_catkin_ws/devel_isolated/rosbag/lib/python2.7/dist-packages:/home/pushyamik/ros_catkin_ws/install_isolated/lib/python2.7/dist-packages
export PKG_CONFIG_PATH=/home/pushyamik/ros_catkin_ws/devel_isolated/rosbag/lib/pkgconfig:/home/pushyamik/ros_catkin_ws/install_isolated/lib/pkgconfig

export CMAKE_PREFIX_PATH=/home/pushyamik/ros_catkin_ws/devel_isolated/rosbag:/home/pushyamik/ros_catkin_ws/install_isolated

export ROS_ETC_DIR=/home/pushyamik/ros_catkin_ws/install_isolated/etc/ros

