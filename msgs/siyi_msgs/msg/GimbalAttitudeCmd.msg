# Gimbal absolute attitude setpoint (fire-and-forget).
#
# Used for "look at this bearing" style commands. Values are clamped
# in the wrapper to the configured mechanical limits before sending.
std_msgs/Header header
float32 yaw_deg
float32 pitch_deg
