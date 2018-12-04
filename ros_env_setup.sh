#!/bin/bash
export TURTLEBOT_3D_SENSOR=kinect
export TURTLEBOT3_MODEL=burger
export ROS_ROOT=<your-folder-path>/install_isolated/share/ros
export ROS_PACKAGE_PATH=<your-folder-path>/src/ros_comm/rosbag:<your-folder-path>/install_isolated/share

export ROS_MASTER_URI=http://pushyamik-u:11311/ #replace with your hostname

export ROS_VERSION=1


export LD_LIBRARY_PATH=<your-folder-path>/devel_isolated/rosbag/lib:<your-folder-path>/install_isolated/lib:$LD_LIBRARY_PATH

export PATH=<your-folder-path>/devel_isolated/rosbag/bin:<your-folder-path>/install_isolated/bin:$PATH


export ROSLISP_PACKAGE_DIRECTORIES=<your-folder-path>/devel_isolated/rosbag/share/common-lisp

export ROS_DISTRO=kinetic

export PYTHONPATH=<your-folder-path>/devel_isolated/rosbag/lib/python2.7/dist-packages:<your-folder-path>/install_isolated/lib/python2.7/dist-packages
export PKG_CONFIG_PATH=<your-folder-path>/devel_isolated/rosbag/lib/pkgconfig:<your-folder-path>/install_isolated/lib/pkgconfig

export CMAKE_PREFIX_PATH=<your-folder-path>/devel_isolated/rosbag:<your-folder-path>/install_isolated

export ROS_ETC_DIR=<your-folder-path>/install_isolated/etc/ros

