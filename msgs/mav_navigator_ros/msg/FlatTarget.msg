# Differentially flat reference for trajectory tracking.
# Port of controller_msgs/msg/FlatTarget.msg from the ROS 1 mavros_controllers repo.

std_msgs/Header header

uint8 type_mask
uint8 IGNORE_SNAP          = 1 # Position Velocity Acceleration Jerk reference
uint8 IGNORE_SNAP_JERK     = 2 # Position Velocity Acceleration reference
uint8 IGNORE_SNAP_JERK_ACC = 4 # Position reference

geometry_msgs/Vector3 position
geometry_msgs/Vector3 velocity
geometry_msgs/Vector3 acceleration
geometry_msgs/Vector3 jerk
geometry_msgs/Vector3 snap
