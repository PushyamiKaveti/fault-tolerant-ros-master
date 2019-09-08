cmake_minimum_required(VERSION 2.8.3)
project(rosmaster)
find_package(catkin REQUIRED)
catkin_package()

catkin_python_setup()

#Pushyami - executable for master_monitor
catkin_install_python(PROGRAMS scripts/master_monitor
  DESTINATION ${CATKIN_PACKAGE_BIN_DESTINATION})

if(CATKIN_ENABLE_TESTING)
  catkin_add_nosetests(test)
endif()
