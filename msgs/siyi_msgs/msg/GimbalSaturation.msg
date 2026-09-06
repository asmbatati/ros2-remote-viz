# Indicates whether the most recent command was clamped to mechanical
# limits. When yaw_saturated is true the tracker should yaw the
# airframe to follow the target.
std_msgs/Header header
bool yaw_saturated
bool pitch_saturated
float32 commanded_yaw_deg
float32 commanded_pitch_deg
