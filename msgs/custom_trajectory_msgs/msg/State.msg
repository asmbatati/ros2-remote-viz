# Vehicle translational and yaw states in 3D

std_msgs/Header header

# Time from start in seconds
float64 time_from_start

# ROS time
builtin_interfaces/Time ros_time

# 3D position
geometry_msgs/Point position

# 3D velocity
geometry_msgs/Vector3 velocity

# 3D acceleration
geometry_msgs/Vector3 acceleration

# 3D jerk
geometry_msgs/Vector3 jerk

# Yaw angle in radians
float64 yaw

# rad/s
float64 yaw_speed

# rad/s/s
float64 yaw_acceleration

# rad/s/s/s
float64 yaw_jerk