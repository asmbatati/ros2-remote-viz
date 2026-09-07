# pkgs/ - packages built from source into the local rviz2 image

An rviz plugin is compiled code. rviz2 `dlopen()`s a panel or display library at
start-up, so a package shipping one cannot be mirrored the way `msgs/` mirrors
interface definitions -- it has to be **built here, for this machine's
architecture**. The robot has already built it, but for its own architecture
(aarch64 on a Jetson), and that binary will not load on an x86 laptop.

Stage the sources straight off the robot:

    rrv pkgs           # what ships rviz plugins there, and what is staged here
    rrv pkgs sync      # copy their sources into this directory
    rrv build          # compile them into the image

Taking the sources from the robot rather than from a local clone is deliberate:
the panels drive the robot's nodes over topics and services, so the two must be
the same version. A local clone that has drifted ahead builds cleanly and then
fails at runtime, which is the hardest kind of failure to read.

To stage a package that is not inside the container:

    rrv pkgs add /path/to/package

The contents here are working copies of other repositories and are not tracked
by git -- run `rrv pkgs sync` after cloning rrv onto a new machine.
