std_msgs/Header header

# State trajectory, a list of time stamped states
custom_trajectory_msgs/State[] states

# Maximum velocity along the entire trajectory, m/s
float64 max_velocity

# Maximum acceleration along the entire trajectory, m/s/s
float64 max_acceleration

# Trajectory quality, e.g. RMSE
float64 quality