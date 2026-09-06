cmake_minimum_required(VERSION 3.8)
project(custom_trajectory_msgs)
find_package(ament_cmake REQUIRED)
find_package(rosidl_default_generators REQUIRED)
find_package(builtin_interfaces REQUIRED)
find_package(geometry_msgs REQUIRED)
find_package(std_msgs REQUIRED)
rosidl_generate_interfaces(${PROJECT_NAME}

  "msg/State.msg"
  "msg/StateTrajectory.msg"
  DEPENDENCIES builtin_interfaces geometry_msgs std_msgs
)
ament_package()
