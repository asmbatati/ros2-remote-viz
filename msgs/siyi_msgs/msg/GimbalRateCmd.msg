# Gimbal velocity command for high-rate tracking control.
#
# Rates are in degrees per second. The siyi_ros2 wrapper converts these
# to the SIYI protocol's -100..100 normalised range using a configurable
# max-rate parameter, then sends them fire-and-forget at the rate of the
# incoming stream. A watchdog will zero the rate if no command arrives
# within the configured timeout.
std_msgs/Header header
float32 yaw_rate_dps
float32 pitch_rate_dps
