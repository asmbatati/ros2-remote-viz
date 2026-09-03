std_msgs/Header header

# Current state of the flight state machine. Values must match
# mav_navigator_ros::FlightState in state_machine/FlightStateTypes.h
uint8 state
string state_name

bool armed
bool offboard
bool odom_healthy
bool setpoint_healthy

string status_message

uint8 UNINITIALIZED    = 0
uint8 WAITING_FOR_HOME = 1
uint8 READY            = 2
uint8 TAKEOFF          = 3
uint8 MISSION          = 4
uint8 HOLD             = 5
uint8 LANDING          = 6
uint8 LANDED           = 7
uint8 EMERGENCY        = 8
