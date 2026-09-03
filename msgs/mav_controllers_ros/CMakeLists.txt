cmake_minimum_required(VERSION 3.8)
project(mav_controllers_ros)
find_package(ament_cmake REQUIRED)
find_package(rosidl_default_generators REQUIRED)
find_package(builtin_interfaces REQUIRED)
find_package(geometry_msgs REQUIRED)
find_package(std_msgs REQUIRED)
rosidl_generate_interfaces(${PROJECT_NAME}

  "msg/ControlErrors.msg"
  "msg/SE3Command.msg"
  "msg/TargetCommand.msg"
  DEPENDENCIES builtin_interfaces geometry_msgs std_msgs
)
ament_package()
