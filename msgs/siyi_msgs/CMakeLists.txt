cmake_minimum_required(VERSION 3.8)
project(siyi_msgs)
find_package(ament_cmake REQUIRED)
find_package(rosidl_default_generators REQUIRED)
find_package(builtin_interfaces REQUIRED)
find_package(std_msgs REQUIRED)
rosidl_generate_interfaces(${PROJECT_NAME}

  "msg/AITrackingTarget.msg"
  "msg/FirmwareVersion.msg"
  "msg/GimbalAttitudeCmd.msg"
  "msg/GimbalAttitude.msg"
  "msg/GimbalInfo.msg"
  "msg/GimbalRateCmd.msg"
  "msg/GimbalSaturation.msg"
  "msg/LaserDistance.msg"
  "msg/ZoomInfo.msg"
  "srv/AutoFocus.srv"
  "srv/CenterGimbal.srv"
  "srv/GetFirmwareVersion.srv"
  "srv/GetGimbalInfo.srv"
  "srv/GetLaserDistance.srv"
  "srv/ManualFocus.srv"
  "srv/ManualZoom.srv"
  "srv/SetAbsoluteZoom.srv"
  "srv/SetGimbalAttitude.srv"
  "srv/SetGimbalMode.srv"
  "srv/SetGimbalSpeed.srv"
  "srv/SetLaserRanging.srv"
  "srv/SetOSD.srv"
  "srv/SetPseudoColor.srv"
  "srv/StartRecording.srv"
  "srv/StopRecording.srv"
  "srv/TakePhoto.srv"
  DEPENDENCIES builtin_interfaces std_msgs
)
ament_package()
